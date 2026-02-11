// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {OracleLib} from "../../libraries/OracleLib.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {AggregatorV3Interface} from "../../chainlink/interfaces/AggregatorV3Interface.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract DSCEngine is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using OracleLib for AggregatorV3Interface;

    error DSCEngine__NeedsMoreThanZero();
    error DSCEngine__TokenNotAllowed(address token);
    error DSCEngine__HealthFactorTooLow(uint256 healthFactor);
    error DSCEngine__LiquidationHealthFactorTooHigh(uint256 healthFactor);
    error DSCEngine__HealthFactorNotImproved(uint256 startHealthFactor, uint256 endHealthFactor);

    event CollateralDeposited(address indexed from, address indexed dst, address indexed token, uint256 amount);
    event CollateralRedeemed(address indexed from, address indexed dst, address indexed token, uint256 amount);

    struct CollateralInfo {
        address priceFeed;
        bool isAllowed;
    }

    uint256 constant TIME_OUT = 6 hours;
    uint256 constant LIQUIDATION_BONUS = 10; // 10%
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
        _checkHealthFactor(sender);
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

    //
    function redeemCollateralForDsc(address collateral, uint256 amountCollateral, uint256 amountDscToBurn)
        external
        isAllowedToken(collateral)
        moreThanZero(amountCollateral)
        moreThanZero(amountDscToBurn)
        nonReentrant
    {
        address sender = _msgSender();
        _burnDsc(sender, sender, amountDscToBurn);
        _redeemCollateral(sender, sender, collateral, amountCollateral);
        _checkHealthFactor(sender);
    }

    function redeemCollateral(address collateral, uint256 amount)
        external
        isAllowedToken(collateral)
        moreThanZero(amount)
        nonReentrant
    {
        address sender = _msgSender();
        _redeemCollateral(sender, sender, collateral, amount);
        _checkHealthFactor(sender);
    }

    function redeemCollateralTo(address dst, address collateral, uint256 amount)
        external
        isAllowedToken(collateral)
        moreThanZero(amount)
        nonReentrant
    {
        address sender = _msgSender();
        _redeemCollateral(sender, dst, collateral, amount);
        _checkHealthFactor(sender);
    }

    function _redeemCollateral(address from, address dst, address collateral, uint256 amount) internal {
        require(dst != address(0), "Invalid destination address");

        _collateralDeposited[from][collateral] -= amount;
        IERC20(collateral).safeTransfer(dst, amount);

        emit CollateralRedeemed(from, dst, collateral, amount);
    }

    function mintDsc(uint256 amountDsc) external moreThanZero(amountDsc) nonReentrant {
        address sender = _msgSender();
        _mintDsc(sender, sender, amountDsc);
        _checkHealthFactor(sender);
    }

    function _mintDsc(address from, address to, uint256 amountDsc) internal {
        _dscMinted[from] += amountDsc;

        i_dsc.mint(to, amountDsc);
    }

    function burnDsc(uint256 amountDsc) external moreThanZero(amountDsc) nonReentrant {
        address sender = _msgSender();
        _burnDsc(sender, sender, amountDsc);
        _checkHealthFactor(sender);
    }

    function _burnDsc(address from, address to, uint256 amountDsc) internal {
        _dscMinted[to] -= amountDsc;

        IERC20(address(i_dsc)).safeTransferFrom(from, address(this), amountDsc);

        i_dsc.burn(amountDsc);
    }

    function liquidate(
        address user,
        address collateral,
        uint256 debtToCover // dscAmount
    )
        external
        isAllowedToken(collateral)
        nonReentrant
    {
        address liquidator = _msgSender();
        uint256 userCollateralBalance = _collateralDeposited[user][collateral];
        uint256 userDebt = _dscMinted[user];

        if (debtToCover == type(uint256).max) {
            if (userCollateralBalance == 0) {
                revert DSCEngine__NeedsMoreThanZero();
            }
            // Debt for this collateral = DSC value of (all this collateral minus bonus)
            uint256 collateralBase =
                (userCollateralBalance * LIQUIDATION_PRECISION) / (LIQUIDATION_PRECISION + LIQUIDATION_BONUS);
            debtToCover = getDscAmountFromCollateral(collateral, collateralBase);
        }

        // Cap to actual debt to avoid underflow in _burnDsc
        if (debtToCover > userDebt) {
            debtToCover = userDebt;
        }

        uint256 startHealthFactor = getHealthFactor(user);
        if (startHealthFactor >= HEALTH_FACTOR_PRECISION) {
            revert DSCEngine__LiquidationHealthFactorTooHigh(startHealthFactor);
        }

        uint256 collateralAmountFromDebtCover = getCollateralAmountFromDsc(collateral, debtToCover);

        uint256 bonusCollateralAmount = (collateralAmountFromDebtCover * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;

        uint256 totalCollateralToRedeem = collateralAmountFromDebtCover + bonusCollateralAmount;

        if (totalCollateralToRedeem > userCollateralBalance) {
            totalCollateralToRedeem = userCollateralBalance;
        }

        _redeemCollateral(user, liquidator, collateral, totalCollateralToRedeem);
        _burnDsc(liquidator, user, debtToCover);

        uint256 endHealthFactor = getHealthFactor(user);
        if (endHealthFactor <= startHealthFactor) {
            revert DSCEngine__HealthFactorNotImproved(startHealthFactor, endHealthFactor);
        }
    }

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

    function getCollateralBalanceOfUser(address user, address token) public view returns (uint256) {
        return _collateralDeposited[user][token];
    }

    function getCollateralValueInUsd(address token, uint256 amount) public view returns (uint256) {
        uint256 price = _getCollateralPrice(token);
        uint256 tokenDecimals = IERC20Metadata(token).decimals();
        return (price * amount) / (10 ** tokenDecimals);
    }

    function _getCollateralPrice(address token) internal view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(_collateralInfo[token].priceFeed);
        (, int256 price,,,) = OracleLib.staleCheckLatestRoundData(priceFeed);

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

    function getCollateralAmountFromDsc(address collateral, uint256 dscAmount) internal view returns (uint256) {
        uint256 price = _getCollateralPrice(collateral);

        uint8 dscDecimals = IERC20Metadata(address(i_dsc)).decimals();
        uint8 collateralDecimals = IERC20Metadata(collateral).decimals();
        uint8 feedDecimals = IERC20Metadata(_collateralInfo[collateral].priceFeed).decimals();
        uint256 collateralAmount =
            Math.mulDiv(dscAmount, (10 ** (collateralDecimals + feedDecimals)), (price * (10 ** dscDecimals)));
        return collateralAmount;
    }

    /// @return dscAmount DSC amount with the same USD value as the given collateral amount
    function getDscAmountFromCollateral(address collateral, uint256 collateralAmount) internal view returns (uint256) {
        uint256 price = _getCollateralPrice(collateral);
        uint8 dscDecimals = IERC20Metadata(address(i_dsc)).decimals();
        uint8 collateralDecimals = IERC20Metadata(collateral).decimals();
        uint8 feedDecimals = IERC20Metadata(_collateralInfo[collateral].priceFeed).decimals();
        return Math.mulDiv(collateralAmount, (price * (10 ** dscDecimals)), (10 ** (collateralDecimals + feedDecimals)));
    }

    function getCollateralTokens() external view returns (address[] memory) {
        return _collateralTokens;
    }

    function getCollateralPriceFeed(address token) external view returns (address) {
        return _collateralInfo[token].priceFeed;
    }

    function _checkHealthFactor(address user) internal view {
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
