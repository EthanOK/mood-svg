// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {Mood, Ownable, Base64} from "../src/Mood.sol";

contract MoodTest is Test {
    Mood public mood;

    address public owner = makeAddr("owner");
    address public alice = makeAddr("alice");

    function setUp() public {
        string memory localTimestampStr = vm.envOr("LOCAL_TIMESTAMP", string("1769652000"));
        uint256 localTimestamp = vm.parseUint(localTimestampStr);
        vm.warp(localTimestamp);

        vm.startPrank(owner);
        mood = new Mood();
        vm.stopPrank();
    }

    function testMint() public {
        vm.startPrank(owner);
        mood.batchMint(alice, 100);
        vm.stopPrank();
    }

    function testMint_Revert_OwnableUnauthorizedAccount() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        vm.startPrank(alice);
        mood.batchMint(alice, 100);
    }

    function test_tokenURI() public {
        uint256 totalSupply = mood.totalSupply();
        uint256 random = uint256(keccak256(abi.encodePacked(block.timestamp, totalSupply)));
        string memory tokenURI = mood.tokenURI((random % totalSupply) + 1);
        string memory JsonString = parseTokenURI(tokenURI);
        console.log(JsonString);
        vm.createDir("output", true);
        vm.writeJson(JsonString, "./output/example.json");
        string memory imageURI = vm.parseJsonString(JsonString, ".image");
        string memory image = parseImageURI(imageURI);
        vm.writeFile("./output/image.svg", image);
    }

    function parseTokenURI(string memory tokenURI) public pure returns (string memory) {
        string memory baseURI = _baseURI();
        // remove baseURI
        tokenURI = vm.replace(tokenURI, baseURI, "");
        bytes memory decodeData = Base64.decode(tokenURI);
        return string(decodeData);
    }

    function parseImageURI(string memory imageURI) public pure returns (string memory) {
        string memory baseURI = "data:image/svg+xml;base64,";
        // remove baseURI
        imageURI = vm.replace(imageURI, baseURI, "");
        bytes memory decodeData = Base64.decode(imageURI);
        return string(decodeData);
    }

    function _baseURI() internal pure returns (string memory) {
        return "data:application/json;base64,";
    }
}
// export LOCAL_TIMESTAMP=$(date +%s) && forge test -vvv
