// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {AggregatorV3Interface} from "../../src/chainlink/interfaces/AggregatorV3Interface.sol";

contract MockV3Aggregator is AggregatorV3Interface {
    int256 private s_price;
    uint8 private s_decimals = 8;
    /// @dev 若不为 0，则 latestRoundData 返回此时间作为 updatedAt（用于测试过期价格）
    uint256 private s_updatedAt;

    constructor(int256 _initialPrice) {
        s_price = _initialPrice;
    }

    function setPrice(int256 _price) external {
        s_price = _price;
    }

    /// @dev 设置 returned updatedAt，用于模拟过期预言机（如 setUpdatedAt(block.timestamp - 7 hours)）
    function setUpdatedAt(uint256 _updatedAt) external {
        s_updatedAt = _updatedAt;
    }

    function decimals() external view override returns (uint8) {
        return s_decimals;
    }

    function description() external pure override returns (string memory) {
        return "Mock V3 Aggregator";
    }

    function version() external pure override returns (uint256) {
        return 1;
    }

    function _getUpdatedAt() private view returns (uint256) {
        return s_updatedAt != 0 ? s_updatedAt : block.timestamp;
    }

    function getRoundData(uint80)
        external
        view
        override
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        roundId = 1;
        answer = s_price;
        startedAt = block.timestamp;
        updatedAt = _getUpdatedAt();
        answeredInRound = 1;
    }

    function latestRoundData()
        external
        view
        override
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        roundId = 1;
        answer = s_price;
        startedAt = block.timestamp;
        updatedAt = _getUpdatedAt();
        answeredInRound = 1;
    }
}
