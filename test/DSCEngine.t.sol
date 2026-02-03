// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {DSCEngine} from "../src/defi/stablecoin/DSCEngine.sol";
import {DecentralizedStableCoin} from "../src/defi/stablecoin/DecentralizedStableCoin.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockV3Aggregator} from "./mocks/MockV3Aggregator.sol";

contract DSCEngineTest is Test {
    DSCEngine public engine;
    DecentralizedStableCoin public dsc;
    ERC20Mock public wEth;
    MockV3Aggregator public ethUsdPriceFeed;

    address public owner = makeAddr("owner");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    uint256 constant ETH_INITIAL_PRICE = 2000e8; // $2000, 8 decimals
    uint256 constant INITIAL_MINT_AMOUNT = 100 ether;

    function setUp() public {
        // 部署 wEth 代币
        vm.prank(owner);
        wEth = new ERC20Mock();
        wEth.mint(alice, INITIAL_MINT_AMOUNT);

        // 部署 ETH/USD 价格预言机 ($2000)
        ethUsdPriceFeed = new MockV3Aggregator(int256(ETH_INITIAL_PRICE));
        ethUsdPriceFeed.setUpdatedAt(block.timestamp);

        // 部署 DSC
        vm.prank(owner);
        dsc = new DecentralizedStableCoin(owner);

        // 部署 DSCEngine
        address[] memory tokenAddresses = new address[](1);
        tokenAddresses[0] = address(wEth);
        address[] memory priceFeedAddresses = new address[](1);
        priceFeedAddresses[0] = address(ethUsdPriceFeed);

        vm.prank(owner);
        engine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));

        // 将 DSC 的 owner 转移给 engine，以便 engine 可以 mint
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
        // 抵押品价值 2000e8 USD，铸造 1000e8 DSC
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

    /* ---------- 超额借贷 (HealthFactorTooLow) ---------- */
    /// @dev 无抵押时铸造应 revert
    function test_MintDsc_RevertWhen_NoCollateral() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__HealthFactorTooLow.selector, 0));
        engine.mintDsc(100e8);
    }

    /// @dev 1 ETH ($2000)，80% 上限 = 1600e8 DSC；铸造超过 1600e8 应 revert
    function test_MintDsc_RevertWhen_HealthFactorTooLow_OverBorrow() public {
        vm.startPrank(alice);
        wEth.approve(address(engine), 1 ether);
        engine.depositCollateral(address(wEth), 1 ether);
        // 抵押品 2000e8 USD，80% = 1600e8，最多可铸 1600e8 DSC；铸 1601e8 → healthFactor < 1e18
        uint256 collateralAdjusted = (2000e8 * 80) / 100;
        uint256 overBorrowAmount = 1601e8;
        uint256 expectedHealthFactor = (collateralAdjusted * 1e18) / overBorrowAmount;
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__HealthFactorTooLow.selector, expectedHealthFactor));
        engine.mintDsc(1601e8);
        vm.stopPrank();
    }

    /// @dev 边界：恰好铸到上限 1600e8 应成功
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

    /* ---------- getCollateralValueInUsd (stale check) ---------- */
    function test_GetCollateralValueInUsd_ReturnsPriceFromFeed() public view {
        uint256 price = engine.getCollateralValueInUsd(address(wEth), 1 ether);
        assertEq(price, uint256(ETH_INITIAL_PRICE));
    }

    function test_GetCollateralValueInUsd_RevertWhen_Stale() public {
        // 将区块时间推进超过 TIME_OUT (6 hours)
        vm.warp(block.timestamp + 7 hours);
        vm.expectRevert("Price feed is stale");
        engine.getCollateralValueInUsd(address(wEth), 1 ether);
    }
}
