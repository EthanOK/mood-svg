// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {DecentralizedStableCoin} from "../../src/defi/stablecoin/DecentralizedStableCoin.sol";

contract DSCInvariantTest is Test {
    address public owner = makeAddr("owner");

    DecentralizedStableCoin dsc;

    function setUp() public {
        dsc = new DecentralizedStableCoin(owner);

        targetContract(address(dsc)); // 让 fuzz 也尝试用 owner 调用，才能覆盖 mint/burn/flagAddress
        targetSender(owner);
    }

    function invariant_TotalSupplyGeqOwnerBalance() public view {
        assertGe(dsc.totalSupply(), dsc.balanceOf(owner));
    }

    function invariant_NoBalanceExceedsTotalSupply() public view {
        assertLe(dsc.balanceOf(owner), dsc.totalSupply());
        assertLe(dsc.balanceOf(address(this)), dsc.totalSupply());
        assertLe(dsc.balanceOf(address(dsc)), dsc.totalSupply());
    }

    function invariant_DecimalsAlwaysEight() public view {
        assertEq(dsc.decimals(), 8);
    }

    function invariant_NameAndSymbolUnchanged() public view {
        assertEq(dsc.name(), "DecentralizedStableCoin");
        assertEq(dsc.symbol(), "DSC");
    }

    function invariant_TotalSupplyNonNegative() public view {
        assertGe(dsc.totalSupply(), 0);
    }
}

// forge test --match-contract DSCInvariantTest -vvv
