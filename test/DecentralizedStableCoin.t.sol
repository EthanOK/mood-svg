// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {DecentralizedStableCoin} from "../src/defi/stablecoin/DecentralizedStableCoin.sol";

contract DecentralizedStableCoinTest is Test {
    DecentralizedStableCoin public dsc;

    address public owner = makeAddr("owner");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    function setUp() public {
        vm.prank(owner);
        dsc = new DecentralizedStableCoin(owner);
    }

    /* ---------- Constructor ---------- */
    function test_Constructor_SetsNameAndSymbol() public view {
        assertEq(dsc.name(), "DecentralizedStableCoin");
        assertEq(dsc.symbol(), "DSC");
    }

    function test_Constructor_SetsOwner() public view {
        assertEq(dsc.owner(), owner);
    }

    function test_Constructor_DecimalsIs8() public view {
        assertEq(dsc.decimals(), 8);
    }

    function test_Constructor_InitialSupplyIsZero() public view {
        assertEq(dsc.totalSupply(), 0);
    }

    /* ---------- Mint ---------- */
    function test_Mint_IncreasesBalance() public {
        vm.prank(owner);
        dsc.mint(alice, 100e8);
        assertEq(dsc.balanceOf(alice), 100e8);
        assertEq(dsc.totalSupply(), 100e8);
    }

    function test_Mint_RevertWhen_NotOwner() public {
        vm.expectRevert();
        vm.prank(alice);
        dsc.mint(alice, 100e8);
    }

    /* ---------- Burn ---------- */
    function test_Burn_DecreasesBalance() public {
        vm.startPrank(owner);
        dsc.mint(owner, 100e8);
        dsc.burn(50e8);
        vm.stopPrank();
        assertEq(dsc.balanceOf(owner), 50e8);
        assertEq(dsc.totalSupply(), 50e8);
    }

    function test_Burn_RevertWhen_NotOwner() public {
        vm.prank(owner);
        dsc.mint(alice, 100e8);
        vm.expectRevert();
        vm.prank(alice);
        dsc.burn(50e8);
    }

    /* ---------- BurnFrom ---------- */
    function test_BurnFrom_DecreasesTargetBalance() public {
        vm.prank(owner);
        dsc.mint(alice, 100e8);
        vm.prank(alice);
        dsc.approve(owner, 40e8);
        vm.prank(owner);
        dsc.burnFrom(alice, 40e8);
        assertEq(dsc.balanceOf(alice), 60e8);
        assertEq(dsc.totalSupply(), 60e8);
    }

    function test_BurnFrom_RevertWhen_NotOwner() public {
        vm.prank(owner);
        dsc.mint(alice, 100e8);
        vm.expectRevert();
        vm.prank(bob);
        dsc.burnFrom(alice, 40e8);
    }

    /* ---------- FlagAddress (Blacklist) ---------- */
    function test_FlagAddress_OnlyOwnerCanFlag() public {
        vm.prank(owner);
        dsc.flagAddress(alice, true);
        assertTrue(dsc.blacklist(alice));

        vm.prank(owner);
        dsc.flagAddress(alice, false);
        assertFalse(dsc.blacklist(alice));
    }

    function test_FlagAddress_RevertWhen_NotOwner() public {
        vm.expectRevert();
        vm.prank(alice);
        dsc.flagAddress(bob, true);
    }

    /* ---------- Blacklist blocks transfer ---------- */
    function test_Blacklist_RevertWhen_TransferFromBlacklisted() public {
        vm.startPrank(owner);
        dsc.mint(alice, 100e8);
        dsc.flagAddress(alice, true);
        vm.stopPrank();

        vm.expectRevert(abi.encodeWithSelector(DecentralizedStableCoin.Blacklisted.selector, alice));
        vm.prank(alice);
        dsc.transfer(bob, 50e8);
    }

    function test_Blacklist_RevertWhen_TransferToBlacklisted() public {
        vm.startPrank(owner);
        dsc.mint(alice, 100e8);
        dsc.flagAddress(bob, true);
        vm.stopPrank();

        vm.expectRevert(abi.encodeWithSelector(DecentralizedStableCoin.Blacklisted.selector, bob));
        vm.prank(alice);
        dsc.transfer(bob, 50e8);
    }

    function test_Blacklist_UnflagAllowsTransfer() public {
        vm.startPrank(owner);
        dsc.mint(alice, 100e8);
        dsc.flagAddress(alice, true);
        dsc.flagAddress(alice, false);
        vm.stopPrank();

        vm.prank(alice);
        dsc.transfer(bob, 50e8);
        assertEq(dsc.balanceOf(alice), 50e8);
        assertEq(dsc.balanceOf(bob), 50e8);
    }

    /* ---------- Normal transfer ---------- */
    function test_Transfer_WorksWhenNotBlacklisted() public {
        vm.prank(owner);
        dsc.mint(alice, 100e8);

        vm.prank(alice);
        dsc.transfer(bob, 30e8);
        assertEq(dsc.balanceOf(alice), 70e8);
        assertEq(dsc.balanceOf(bob), 30e8);
    }
}
