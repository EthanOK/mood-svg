// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console, stdError} from "forge-std/Test.sol";
import {DSCEngine} from "../src/defi/stablecoin/DSCEngine.sol";
import {DecentralizedStableCoin} from "../src/defi/stablecoin/DecentralizedStableCoin.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockV3Aggregator} from "./mocks/MockV3Aggregator.sol";

contract DSCEngineTest is Test {
    event CollateralDeposited(address indexed from, address indexed dst, address indexed token, uint256 amount);
    event CollateralRedeemed(address indexed from, address indexed dst, address indexed token, uint256 amount);

    DSCEngine public engine;
    DecentralizedStableCoin public dsc;
    ERC20Mock public wEth;
    MockV3Aggregator public ethUsdPriceFeed;

    address public owner = makeAddr("owner");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    uint8 constant PRICE_FEED_DECIMALS = 8;
    uint256 constant ETH_INITIAL_PRICE = 2000 * 10 ** PRICE_FEED_DECIMALS; // $2000
    uint256 constant INITIAL_MINT_AMOUNT = 100 ether;

    function setUp() public {
        // Deploy wEth token
        vm.prank(owner);
        wEth = new ERC20Mock();
        wEth.mint(alice, INITIAL_MINT_AMOUNT);

        // Deploy ETH/USD price feed ($2000)
        ethUsdPriceFeed = new MockV3Aggregator(PRICE_FEED_DECIMALS, int256(ETH_INITIAL_PRICE));

        // Deploy DSC
        vm.prank(owner);
        dsc = new DecentralizedStableCoin(owner);

        // Deploy DSCEngine
        address[] memory tokenAddresses = new address[](1);
        tokenAddresses[0] = address(wEth);
        address[] memory priceFeedAddresses = new address[](1);
        priceFeedAddresses[0] = address(ethUsdPriceFeed);

        vm.prank(owner);
        engine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));

        // Transfer DSC ownership to engine so it can mint
        vm.prank(owner);
        dsc.transferOwnership(address(engine));
    }

    /* ---------- Constructor ---------- */
    function test_Constructor_RevertWhen_InvalidPriceFeedAddress() public {
        address[] memory tokenAddresses = new address[](1);
        tokenAddresses[0] = address(wEth);
        address[] memory priceFeedAddresses = new address[](1);
        priceFeedAddresses[0] = address(0);

        vm.expectRevert("Invalid price feed address");
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    /* ---------- depositCollateral ---------- */
    function test_DepositCollateral_UpdatesBalanceAndEmitsEvent() public {
        uint256 depositAmount = 1 ether;
        vm.startPrank(alice);
        wEth.approve(address(engine), depositAmount);
        engine.depositCollateral(address(wEth), depositAmount);
        vm.stopPrank();

        (uint256 totalDscMinted, uint256 collateralValueInUsd) = engine.getAccountInformation(alice);
        assertEq(totalDscMinted, 0);
        assertEq(collateralValueInUsd, 2000e8); // 1 ETH * $2000, 8 decimals
        assertEq(wEth.balanceOf(alice), INITIAL_MINT_AMOUNT - depositAmount);
        assertEq(wEth.balanceOf(address(engine)), depositAmount);
    }

    function test_DepositCollateral_RevertWhen_AmountZero() public {
        vm.prank(alice);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        engine.depositCollateral(address(wEth), 0);
    }

    function test_DepositCollateral_RevertWhen_TokenNotAllowed() public {
        ERC20Mock randomToken = new ERC20Mock();
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__TokenNotAllowed.selector, address(randomToken)));
        engine.depositCollateral(address(randomToken), 1 ether);
    }

    function test_DepositCollateral_AccumulatesMultipleDeposits() public {
        vm.startPrank(alice);
        wEth.approve(address(engine), 2 ether);
        engine.depositCollateral(address(wEth), 1 ether);
        engine.depositCollateral(address(wEth), 1 ether);
        vm.stopPrank();

        (, uint256 collateralValueInUsd) = engine.getAccountInformation(alice);
        assertEq(collateralValueInUsd, 4000e8); // 2 ETH * $2000
    }

    /* ---------- depositCollateralAndMintDsc ---------- */
    function test_DepositCollateralAndMintDsc_UpdatesCollateralAndMintsDsc() public {
        uint256 collateralAmount = 1 ether;
        uint256 mintDscAmount = 1000e8;
        vm.startPrank(alice);
        wEth.approve(address(engine), collateralAmount);
        engine.depositCollateralAndMintDsc(address(wEth), collateralAmount, mintDscAmount);
        vm.stopPrank();

        (uint256 totalDscMinted, uint256 collateralValueInUsd) = engine.getAccountInformation(alice);
        assertEq(totalDscMinted, mintDscAmount);
        assertEq(collateralValueInUsd, 2000e8); // 1 ETH * $2000
        assertEq(wEth.balanceOf(alice), INITIAL_MINT_AMOUNT - collateralAmount);
        assertEq(wEth.balanceOf(address(engine)), collateralAmount);
        assertEq(dsc.balanceOf(alice), mintDscAmount);
    }

    function test_DepositCollateralAndMintDsc_EmitsCollateralDeposited() public {
        uint256 collateralAmount = 1 ether;
        uint256 mintDscAmount = 500e8;
        vm.startPrank(alice);
        wEth.approve(address(engine), collateralAmount);
        vm.expectEmit(true, true, true, true);
        emit CollateralDeposited(alice, alice, address(wEth), collateralAmount);
        engine.depositCollateralAndMintDsc(address(wEth), collateralAmount, mintDscAmount);
        vm.stopPrank();
    }

    function test_DepositCollateralAndMintDsc_RevertWhen_CollateralAmountZero() public {
        vm.prank(alice);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        engine.depositCollateralAndMintDsc(address(wEth), 0, 100e8);
    }

    function test_DepositCollateralAndMintDsc_RevertWhen_MintDscAmountZero() public {
        vm.startPrank(alice);
        wEth.approve(address(engine), 1 ether);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        engine.depositCollateralAndMintDsc(address(wEth), 1 ether, 0);
        vm.stopPrank();
    }

    function test_DepositCollateralAndMintDsc_RevertWhen_TokenNotAllowed() public {
        ERC20Mock randomToken = new ERC20Mock();
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__TokenNotAllowed.selector, address(randomToken)));
        engine.depositCollateralAndMintDsc(address(randomToken), 1 ether, 100e8);
    }

    function test_DepositCollateralAndMintDsc_RevertWhen_HealthFactorTooLow() public {
        uint256 collateralAmount = 1 ether;
        uint256 overMintAmount = 1601e8;
        uint256 collateralAdjusted = (2000e8 * 80) / 100;
        uint256 expectedHealthFactor = (collateralAdjusted * 1e18) / overMintAmount;

        vm.startPrank(alice);
        wEth.approve(address(engine), collateralAmount);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__HealthFactorTooLow.selector, expectedHealthFactor));
        engine.depositCollateralAndMintDsc(address(wEth), collateralAmount, overMintAmount);
        vm.stopPrank();
    }

    function test_DepositCollateralAndMintDsc_SucceedsAtMaxAllowed() public {
        uint256 collateralAmount = 1 ether;
        uint256 mintDscAmount = 1600e8;

        vm.startPrank(alice);
        wEth.approve(address(engine), collateralAmount);
        engine.depositCollateralAndMintDsc(address(wEth), collateralAmount, mintDscAmount);
        vm.stopPrank();

        assertEq(dsc.balanceOf(alice), mintDscAmount);
        uint256 hf = engine.getHealthFactor(alice);
        assertEq(hf, 1e18);
    }

    /* ---------- getCollateralValueInUsd / getUserCollateralValueInUsd ---------- */
    function test_GetCollateralValueInUsd_ReturnsCorrectValue() public view {
        // 1 ether (18 decimals) * 2000e8 (price 8 decimals) / 1e18 = 2000e8
        uint256 value = engine.getCollateralValueInUsd(address(wEth), 1 ether);
        assertEq(value, 2000e8);
    }

    /* ---------- getAccountInformation ---------- */
    function test_GetAccountInformation_ReturnsZeroWhenNoActivity() public view {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = engine.getAccountInformation(alice);
        assertEq(totalDscMinted, 0);
        assertEq(collateralValueInUsd, 0);
    }

    /* ---------- getHealthFactor ---------- */
    function test_GetHealthFactor_ReturnsMaxWhenNoDscMinted() public {
        vm.startPrank(alice);
        wEth.approve(address(engine), 1 ether);
        engine.depositCollateral(address(wEth), 1 ether);
        vm.stopPrank();

        uint256 healthFactor = engine.getHealthFactor(alice);
        assertEq(healthFactor, type(uint256).max);
    }

    function test_GetHealthFactor_ReturnsCorrectValueAfterMint() public {
        vm.startPrank(alice);
        wEth.approve(address(engine), 1 ether);
        engine.depositCollateral(address(wEth), 1 ether);
        // Collateral value 2000e8 USD, mint 1000e8 DSC
        // collateralAdjusted = 2000e8 * 80 / 100 = 1600e8, healthFactor = 1600e8 * 1e18 / 1000e8 = 1.6e18
        engine.mintDsc(1000e8);
        vm.stopPrank();

        uint256 healthFactor = engine.getHealthFactor(alice);
        assertEq(healthFactor, 1.6e18);
    }

    /* ---------- mintDsc ---------- */
    function test_MintDsc_IncreasesBalanceAndMintedAmount() public {
        vm.startPrank(alice);
        wEth.approve(address(engine), 1 ether);
        engine.depositCollateral(address(wEth), 1 ether);
        engine.mintDsc(500e8);
        vm.stopPrank();

        (uint256 totalDscMinted,) = engine.getAccountInformation(alice);
        assertEq(totalDscMinted, 500e8);
        assertEq(dsc.balanceOf(alice), 500e8);
    }

    function test_MintDsc_RevertWhen_AmountZero() public {
        vm.prank(alice);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        engine.mintDsc(0);
    }

    /* ---------- Over-borrowing (HealthFactorTooLow) ---------- */
    /// @dev Minting with no collateral should revert
    function test_MintDsc_RevertWhen_NoCollateral() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__HealthFactorTooLow.selector, 0));
        engine.mintDsc(100e8);
    }

    /// @dev 1 ETH ($2000), 80% cap = 1600e8 DSC; minting over 1600e8 should revert
    function test_MintDsc_RevertWhen_HealthFactorTooLow_OverBorrow() public {
        vm.startPrank(alice);
        wEth.approve(address(engine), 1 ether);
        engine.depositCollateral(address(wEth), 1 ether);
        // Collateral 2000e8 USD, 80% = 1600e8 max DSC; mint 1601e8 -> healthFactor < 1e18
        uint256 collateralAdjusted = (2000e8 * 80) / 100;
        uint256 overBorrowAmount = 1601e8;
        uint256 expectedHealthFactor = (collateralAdjusted * 1e18) / overBorrowAmount;
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__HealthFactorTooLow.selector, expectedHealthFactor));
        engine.mintDsc(1601e8);
        vm.stopPrank();
    }

    /// @dev Boundary: minting exactly at cap 1600e8 should succeed
    function test_MintDsc_SucceedsAtMaxAllowed() public {
        vm.startPrank(alice);
        wEth.approve(address(engine), 1 ether);
        engine.depositCollateral(address(wEth), 1 ether);
        engine.mintDsc(1600e8);
        vm.stopPrank();

        assertEq(dsc.balanceOf(alice), 1600e8);
        uint256 hf = engine.getHealthFactor(alice);
        assertEq(hf, 1e18);
    }

    /* ---------- redeemCollateral / redeemCollateralTo ---------- */
    function test_RedeemCollateral_DecreasesCollateralAndTransfersToken() public {
        uint256 depositAmount = 1 ether;
        uint256 redeemAmount = 0.4 ether;

        vm.startPrank(alice);
        wEth.approve(address(engine), depositAmount);
        engine.depositCollateral(address(wEth), depositAmount);

        uint256 aliceBalanceBefore = wEth.balanceOf(alice);
        engine.redeemCollateral(address(wEth), redeemAmount);
        vm.stopPrank();

        (uint256 totalDscMinted, uint256 collateralValueInUsd) = engine.getAccountInformation(alice);
        assertEq(totalDscMinted, 0);
        assertEq(collateralValueInUsd, 1200e8); // 0.6 ETH * $2000

        assertEq(wEth.balanceOf(alice), aliceBalanceBefore + redeemAmount);
        assertEq(wEth.balanceOf(address(engine)), depositAmount - redeemAmount);
    }

    function test_RedeemCollateral_EmitsCollateralRedeemed() public {
        uint256 depositAmount = 1 ether;
        uint256 redeemAmount = 0.25 ether;

        vm.startPrank(alice);
        wEth.approve(address(engine), depositAmount);
        engine.depositCollateral(address(wEth), depositAmount);

        vm.expectEmit(true, true, true, true);
        emit CollateralRedeemed(alice, alice, address(wEth), redeemAmount);
        engine.redeemCollateral(address(wEth), redeemAmount);
        vm.stopPrank();
    }

    function test_RedeemCollateral_RevertWhen_AmountZero() public {
        vm.prank(alice);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        engine.redeemCollateral(address(wEth), 0);
    }

    function test_RedeemCollateral_RevertWhen_TokenNotAllowed() public {
        ERC20Mock randomToken = new ERC20Mock();
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__TokenNotAllowed.selector, address(randomToken)));
        engine.redeemCollateral(address(randomToken), 1 ether);
    }

    function test_RedeemCollateral_RevertWhen_RedeemMoreThanDeposited() public {
        vm.startPrank(alice);
        wEth.approve(address(engine), 1 ether);
        engine.depositCollateral(address(wEth), 1 ether);

        vm.expectRevert(stdError.arithmeticError);
        engine.redeemCollateral(address(wEth), 2 ether);
        vm.stopPrank();
    }

    function test_RedeemCollateral_RevertWhen_HealthFactorTooLow_AfterRedeem() public {
        // Deposit 1 ETH ($2000), mint 1000e8 DSC, then try to redeem 0.5 ETH.
        // Remaining collateral = 1000e8 USD, adjusted = 800e8 => healthFactor = 0.8e18 < 1e18
        uint256 depositAmount = 1 ether;
        uint256 mintAmount = 1000e8;
        uint256 redeemAmount = 0.5 ether;
        uint256 expectedHealthFactor = 0.8e18;

        vm.startPrank(alice);
        wEth.approve(address(engine), depositAmount);
        engine.depositCollateral(address(wEth), depositAmount);
        engine.mintDsc(mintAmount);

        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__HealthFactorTooLow.selector, expectedHealthFactor));
        engine.redeemCollateral(address(wEth), redeemAmount);
        vm.stopPrank();
    }

    function test_RedeemCollateralTo_TransfersToDstAndUpdatesFrom() public {
        uint256 depositAmount = 1 ether;
        uint256 redeemAmount = 0.1 ether;

        vm.startPrank(alice);
        wEth.approve(address(engine), depositAmount);
        engine.depositCollateral(address(wEth), depositAmount);

        uint256 bobBalanceBefore = wEth.balanceOf(bob);
        engine.redeemCollateralTo(bob, address(wEth), redeemAmount);
        vm.stopPrank();

        (, uint256 collateralValueInUsd) = engine.getAccountInformation(alice);
        assertEq(collateralValueInUsd, 1800e8); // 0.9 ETH * $2000
        assertEq(wEth.balanceOf(bob), bobBalanceBefore + redeemAmount);
    }

    function test_RedeemCollateralTo_RevertWhen_DstZeroAddress() public {
        uint256 depositAmount = 1 ether;
        vm.startPrank(alice);
        wEth.approve(address(engine), depositAmount);
        engine.depositCollateral(address(wEth), depositAmount);

        vm.expectRevert(bytes("Invalid destination address"));
        engine.redeemCollateralTo(address(0), address(wEth), 0.1 ether);
        vm.stopPrank();
    }

    /* ---------- redeemCollateralForDsc ---------- */
    function test_RedeemCollateralForDsc_BurnsDscAndRedeemsCollateral() public {
        uint256 depositAmount = 1 ether;
        uint256 mintAmount = 500e8;
        uint256 burnAmount = 200e8;
        uint256 redeemAmount = 0.2 ether;

        vm.startPrank(alice);
        wEth.approve(address(engine), depositAmount);
        engine.depositCollateral(address(wEth), depositAmount);
        engine.mintDsc(mintAmount);

        // burnDsc path pulls DSC via transferFrom
        dsc.approve(address(engine), burnAmount);

        uint256 aliceWethBefore = wEth.balanceOf(alice);
        engine.redeemCollateralForDsc(address(wEth), redeemAmount, burnAmount);
        vm.stopPrank();

        // DSC minted should decrease, DSC balance should decrease by burnAmount
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = engine.getAccountInformation(alice);
        assertEq(totalDscMinted, mintAmount - burnAmount);
        assertEq(dsc.balanceOf(alice), mintAmount - burnAmount);

        // Collateral should decrease and tokens should be returned
        assertEq(collateralValueInUsd, 1600e8); // 0.8 ETH * $2000
        assertEq(wEth.balanceOf(alice), aliceWethBefore + redeemAmount);
        assertEq(wEth.balanceOf(address(engine)), depositAmount - redeemAmount);
    }

    function test_RedeemCollateralForDsc_EmitsCollateralRedeemed() public {
        uint256 depositAmount = 1 ether;
        uint256 mintAmount = 500e8;
        uint256 burnAmount = 100e8;
        uint256 redeemAmount = 0.1 ether;

        vm.startPrank(alice);
        wEth.approve(address(engine), depositAmount);
        engine.depositCollateral(address(wEth), depositAmount);
        engine.mintDsc(mintAmount);
        dsc.approve(address(engine), burnAmount);

        vm.expectEmit(true, true, true, true);
        emit CollateralRedeemed(alice, alice, address(wEth), redeemAmount);
        engine.redeemCollateralForDsc(address(wEth), redeemAmount, burnAmount);
        vm.stopPrank();
    }

    function test_RedeemCollateralForDsc_RevertWhen_CollateralAmountZero() public {
        vm.prank(alice);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        engine.redeemCollateralForDsc(address(wEth), 0, 1e8);
    }

    function test_RedeemCollateralForDsc_RevertWhen_BurnAmountZero() public {
        vm.prank(alice);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        engine.redeemCollateralForDsc(address(wEth), 1, 0);
    }

    function test_RedeemCollateralForDsc_RevertWhen_TokenNotAllowed() public {
        ERC20Mock randomToken = new ERC20Mock();
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__TokenNotAllowed.selector, address(randomToken)));
        engine.redeemCollateralForDsc(address(randomToken), 1 ether, 1e8);
    }

    function test_RedeemCollateralForDsc_RevertWhen_HealthFactorTooLow_AfterRedeem() public {
        // Deposit 1 ETH ($2000), mint 1500e8 DSC, burn 1e8, then redeem 0.3 ETH.
        // Remaining collateral = 0.7 ETH => 1400e8 USD; adjusted = 1120e8
        // Remaining debt = 1499e8, so healthFactor = 1120/1499 * 1e18 < 1e18 => revert
        uint256 depositAmount = 1 ether;
        uint256 mintAmount = 1500e8;
        uint256 burnAmount = 1e8;
        uint256 redeemAmount = 0.3 ether;

        uint256 collateralAdjusted = (1400e8 * 80) / 100; // 1120e8
        uint256 remainingDebt = mintAmount - burnAmount; // 1499e8
        uint256 expectedHealthFactor = (collateralAdjusted * 1e18) / remainingDebt;

        vm.startPrank(alice);
        wEth.approve(address(engine), depositAmount);
        engine.depositCollateral(address(wEth), depositAmount);
        engine.mintDsc(mintAmount);
        dsc.approve(address(engine), burnAmount);

        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__HealthFactorTooLow.selector, expectedHealthFactor));
        engine.redeemCollateralForDsc(address(wEth), redeemAmount, burnAmount);
        vm.stopPrank();
    }

    /* ---------- getCollateralValueInUsd (stale check) ---------- */
    function test_GetCollateralValueInUsd_ReturnsPriceFromFeed() public view {
        uint256 price = engine.getCollateralValueInUsd(address(wEth), 1 ether);
        assertEq(price, uint256(ETH_INITIAL_PRICE));
    }

    function test_GetCollateralValueInUsd_RevertWhen_Stale() public {
        // Warp block time past TIME_OUT (6 hours)
        vm.warp(block.timestamp + 7 hours);
        vm.expectRevert("Price feed is stale");
        engine.getCollateralValueInUsd(address(wEth), 1 ether);
    }
}

// forge test --match-contract DSCEngineTest -vvv
