// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/defi/stablecoin/DSCEngine.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {DecentralizedStableCoin} from "../../src/defi/stablecoin/DecentralizedStableCoin.sol";

contract DSCEngineHandler is Test {
    DSCEngine public engine;
    DecentralizedStableCoin public dsc;

    ERC20Mock public wEth;
    ERC20Mock public wBtc;

    uint256 public timesMintIsCalled;
    address[] usersWithCollateralDeposited;

    constructor(address _engine, address _dsc) {
        engine = DSCEngine(_engine);
        dsc = DecentralizedStableCoin(_dsc);
        address[] memory collateralTokens = engine.getCollateralTokens();
        wEth = ERC20Mock(collateralTokens[0]);
        wBtc = ERC20Mock(collateralTokens[1]);
    }

    function mintDsc(uint256 amountDsc, uint256 addressSeed) public {
        if (usersWithCollateralDeposited.length == 0) {
            return;
        }
        address sender = usersWithCollateralDeposited[addressSeed % usersWithCollateralDeposited.length];
        // address sender = msg.sender;
        amountDsc = bound(amountDsc, 1, type(uint64).max);

        (uint256 totalDscMinted, uint256 collateralValueInUsd) = engine.getAccountInformation(sender);

        int256 maxDscToMint = int256((collateralValueInUsd * 80) / 100) - int256(totalDscMinted);

        if (maxDscToMint <= 0) {
            return;
        }

        amountDsc = bound(amountDsc, 1, uint256(maxDscToMint));

        vm.startPrank(sender);
        engine.mintDsc(amountDsc);
        vm.stopPrank();

        timesMintIsCalled++;
    }

    function depositCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        amountCollateral = bound(amountCollateral, 1, type(uint64).max);
        ERC20Mock collateral = _getCollateralAddressFromSeed(collateralSeed);

        vm.startPrank(msg.sender);
        (collateral).mint(msg.sender, amountCollateral);
        (collateral).approve(address(engine), amountCollateral);

        engine.depositCollateral(address(collateral), amountCollateral);
        vm.stopPrank();
    }

    function redeemCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateral = _getCollateralAddressFromSeed(collateralSeed);
        uint256 maxCollateralToRedeem = engine.getCollateralBalanceOfUser(msg.sender, address(collateral));

        if (maxCollateralToRedeem == 0) {
            return;
        }

        amountCollateral = bound(amountCollateral, 1, maxCollateralToRedeem);

        vm.startPrank(msg.sender);
        engine.redeemCollateral(address(collateral), amountCollateral);
        vm.stopPrank();
        usersWithCollateralDeposited.push(msg.sender);
    }

    function _getCollateralAddressFromSeed(uint256 collateralSeed) internal view returns (ERC20Mock) {
        if ((collateralSeed) % 2 == 0) {
            return (wEth);
        }
        return (wBtc);
    }
}
