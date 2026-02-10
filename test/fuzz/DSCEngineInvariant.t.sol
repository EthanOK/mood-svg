// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";
import {DSCEngine} from "../../src/defi/stablecoin/DSCEngine.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {DecentralizedStableCoin} from "../../src/defi/stablecoin/DecentralizedStableCoin.sol";
import {DSCEngineHandler} from "./DSCEngineHandler.t.sol";

contract DSCEngineInvariantTest is Test {
    address public owner = makeAddr("owner");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    DSCEngine public engine;
    DecentralizedStableCoin public dsc;
    ERC20Mock public wEth;
    ERC20Mock public wBtc;
    MockV3Aggregator public ethUsdPriceFeed;
    MockV3Aggregator public btcUsdPriceFeed;
    DSCEngineHandler public handler;

    uint8 constant PRICE_FEED_DECIMALS = 8;
    uint256 constant ETH_INITIAL_PRICE = 2000 * 10 ** PRICE_FEED_DECIMALS; // $
    uint256 constant BTC_INITIAL_PRICE = 80000 * 10 ** PRICE_FEED_DECIMALS; // $80000
    uint256 constant INITIAL_MINT_AMOUNT = 100 ether;

    function setUp() public {
        wEth = new ERC20Mock();
        wEth.mint(alice, INITIAL_MINT_AMOUNT);

        wBtc = new ERC20Mock();
        wBtc.mint(bob, INITIAL_MINT_AMOUNT);

        // Deploy ETH/USD price feed ($2000)
        ethUsdPriceFeed = new MockV3Aggregator(PRICE_FEED_DECIMALS, int256(ETH_INITIAL_PRICE));
        btcUsdPriceFeed = new MockV3Aggregator(PRICE_FEED_DECIMALS, int256(BTC_INITIAL_PRICE));

        // Deploy DSC
        vm.prank(owner);
        dsc = new DecentralizedStableCoin(owner);

        // Deploy DSCEngine
        address[] memory tokenAddresses = new address[](2);
        tokenAddresses[0] = address(wEth);
        tokenAddresses[1] = address(wBtc);
        address[] memory priceFeedAddresses = new address[](2);
        priceFeedAddresses[0] = address(ethUsdPriceFeed);
        priceFeedAddresses[1] = address(btcUsdPriceFeed);

        vm.prank(owner);
        engine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));

        // Transfer DSC ownership to engine so it can mint
        vm.prank(owner);
        dsc.transferOwnership(address(engine));

        handler = new DSCEngineHandler(address(engine), address(dsc));

        targetContract(address(handler));
    }

    function invariant_TotalCollateralValueGeTotalSupply() public view {
        uint256 totalSupply = dsc.totalSupply();
        uint256 totalWethDeposited = wEth.balanceOf(address(engine));
        uint256 totalWbtcDeposited = wBtc.balanceOf(address(engine));

        uint256 wethValue = engine.getCollateralValueInUsd(address(wEth), totalWethDeposited);
        uint256 btcValue = engine.getCollateralValueInUsd(address(wBtc), totalWbtcDeposited);

        console.log("wethValue", wethValue);
        console.log("btcValue", btcValue);
        console.log("totalSupply", totalSupply);
        console.log("timesMintIsCalled", handler.timesMintIsCalled());

        assertGe(wethValue + btcValue, totalSupply);
    }

    function invariant_GettersShouldNotRevert() public view {
        engine.getCollateralTokens();
        engine.getCollateralValueInUsd(address(wEth), 1 ether);
        engine.getCollateralValueInUsd(address(wBtc), 1 ether);
        engine.getAccountInformation(msg.sender);
        engine.getHealthFactor(msg.sender);
    }
}
