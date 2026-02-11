// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {AggregatorV3Interface} from "../chainlink/interfaces/AggregatorV3Interface.sol";

library OracleLib {
    error OracleLib__StalePrice();

    uint256 constant TIME_OUT = 3 hours;

    function staleCheckLatestRoundData(AggregatorV3Interface priceFeed)
        internal
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        (uint80 _roundId, int256 _answer, uint256 _startedAt, uint256 _updatedAt, uint80 _answeredInRound) =
            priceFeed.latestRoundData();

        uint256 timeSinceLastUpdate = block.timestamp - _updatedAt;
        if (timeSinceLastUpdate > TIME_OUT) {
            revert OracleLib__StalePrice();
        }

        return (_roundId, _answer, _startedAt, _updatedAt, _answeredInRound);
    }
}
