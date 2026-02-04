// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {AggregatorV3Interface} from "../../chainlink/interfaces/AggregatorV3Interface.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract DSCEngine is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    error DSCEngine__NeedsMoreThanZero();
    error DSCEngine__TokenNotAllowed(address token);
    error DSCEngine__HealthFactorTooLow(uint256 healthFactor);

    event CollateralDeposited(address indexed from, address indexed dst, address indexed token, uint256 amount);
    event CollateralRedeemed(address indexed from, address indexed dst, address indexed token, uint256 amount);

    struct CollateralInfo {
        address priceFeed;
        bool isAllowed;
    }

    uint256 constant TIME_OUT = 6 hours;
    uint256 private constant LIQUIDATION_THRESHOLD = 80;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant HEALTH_FACTOR_PRECISION = 1e18;

    DecentralizedStableCoin private immutable i_dsc;

    mapping(address => CollateralInfo) private _collateralInfo;

    address[] private _collateralTokens;

    // user => token => amount
    mapping(address => mapping(address => uint256)) private _collateralDeposited;
    // user => minted
    mapping(address => uint256) private _dscMinted;

    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address dscAddress)
        Ownable(_msgSender())
    {
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            address token = tokenAddresses[i];
            address priceFeed = priceFeedAddresses[i];
            require(priceFeed != address(0), "Invalid price feed address");
            _collateralInfo[token] = CollateralInfo({priceFeed: priceFeed, isAllowed: true});
            _collateralTokens.push(token);
        }
        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    function depositCollateralAndMintDsc(address collateral, uint256 collateralAmount, uint256 mintDscAmount)
        external
        isAllowedToken(collateral)
        moreThanZero(collateralAmount)
        moreThanZero(mintDscAmount)
        nonReentrant
    {
        address sender = _msgSender();
        _depositCollateral(sender, sender, collateral, collateralAmount);
        _mintDsc(sender, sender, mintDscAmount);
    }

    function depositCollateral(address collateral, uint256 amount)
        external
        isAllowedToken(collateral)
        moreThanZero(amount)
        nonReentrant
    {
        _depositCollateral(_msgSender(), _msgSender(), collateral, amount);
    }

    function depositCollateralTo(address dst, address collateral, uint256 amount)
        external
        isAllowedToken(collateral)
        moreThanZero(amount)
        nonReentrant
    {
        _depositCollateral(_msgSender(), dst, collateral, amount);
    }

    function _depositCollateral(address from, address dst, address collateral, uint256 amount) internal {
        require(dst != address(0), "Invalid destination address");
        _collateralDeposited[dst][collateral] += amount;
        IERC20(collateral).safeTransferFrom(from, address(this), amount);
        emit CollateralDeposited(from, dst, collateral, amount);
    }

    function redeemCollateralForDsc() external {}

    function redeemCollateral(address collateral, uint256 amount)
        external
        isAllowedToken(collateral)
        moreThanZero(amount)
        nonReentrant
    {
        address sender = _msgSender();
        _redeemCollateral(sender, sender, collateral, amount);
    }

    function redeemCollateralTo(address dst, address collateral, uint256 amount)
        external
        isAllowedToken(collateral)
        moreThanZero(amount)
        nonReentrant
    {
        address sender = _msgSender();
        _redeemCollateral(sender, dst, collateral, amount);
    }

    function _redeemCollateral(address from, address dst, address collateral, uint256 amount) internal {
        require(dst != address(0), "Invalid destination address");
        
        _collateralDeposited[from][collateral] -= amount;
        IERC20(collateral).safeTransfer(dst, amount);

        _checkHealthFactor(from);

        emit CollateralRedeemed(from, dst, collateral, amount);
    }

    function mintDsc(uint256 amountDsc) external moreThanZero(amountDsc) nonReentrant {
        address sender = _msgSender();
        _mintDsc(sender, sender, amountDsc);
    }

    function _mintDsc(address from, address to, uint256 amountDsc) internal {
        _dscMinted[from] += amountDsc;

        _checkHealthFactor(from);

        i_dsc.mint(to, amountDsc);
    }

    function burnDsc() external {}

    function liquidate() external {}

    function getHealthFactor(address user) public view returns (uint256) {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);

        uint256 DSC_DECIMALS = IERC20Metadata(address(i_dsc)).decimals();
        uint256 CHAINLINK_DECIMALS = 8;

        totalDscMinted = (totalDscMinted * 10 ** (CHAINLINK_DECIMALS)) / (10 ** DSC_DECIMALS);

        return _calculateHealthFactor(totalDscMinted, collateralValueInUsd);
    }

    function getAccountInformation(address user)
        external
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        return _getAccountInformation(user);
    }

    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        totalDscMinted = _dscMinted[user];
        collateralValueInUsd = getUserCollateralValueInUsd(user);
    }

    function getUserCollateralValueInUsd(address user) public view returns (uint256 totalCollateralValueInUsd) {
        for (uint256 i = 0; i < _collateralTokens.length; i++) {
            address token = _collateralTokens[i];
            uint256 amount = _collateralDeposited[user][token];
            totalCollateralValueInUsd += getCollateralValueInUsd(token, amount);
        }
    }

    function getCollateralValueInUsd(address token, uint256 amount) public view returns (uint256) {
        uint256 price = _getCollateralPrice(token);
        uint256 tokenDecimals = IERC20Metadata(token).decimals();
        return (price * amount) / (10 ** tokenDecimals);
    }

    function _getCollateralPrice(address token) internal view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(_collateralInfo[token].priceFeed);
        (, int256 price,, uint256 updatedAt,) = priceFeed.latestRoundData();
        require(block.timestamp - updatedAt <= TIME_OUT, "Price feed is stale");
        return uint256(price);
    }

    function _calculateHealthFactor(uint256 totalDscMinted, uint256 collateralValueInUsd)
        internal
        pure
        returns (uint256)
    {
        if (totalDscMinted == 0) return type(uint256).max;
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return ((collateralAdjustedForThreshold) * HEALTH_FACTOR_PRECISION) / totalDscMinted;
    }

    function _checkHealthFactor(address user) internal {
        uint256 healthFactor = getHealthFactor(user);
        if (healthFactor < HEALTH_FACTOR_PRECISION) {
            revert DSCEngine__HealthFactorTooLow(healthFactor);
        }
    }

    modifier moreThanZero(uint256 amount) {
        if (amount <= 0) {
            revert DSCEngine__NeedsMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (!_collateralInfo[token].isAllowed) {
            revert DSCEngine__TokenNotAllowed(token);
        }
        _;
    }
}
