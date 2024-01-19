//SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/**
 * @title OracleLib
 * @author Yoni Keselbrener
 * @notice OracleLib checks for oracle stale data.
 * If a price is stale, the function will revert, and render the YUSDEngine unusable - this is by design.
 * The oracle is the only source of truth for the YUSDEngine, and if it is not working properly, the system should not be used.
 * We want the YUSDEngine to freeze if prices become stale
 */
library OracleLib {
    error OracleLib__StalePrice();

    uint256 public constant TIMEOUT = 3 hours;

    function staleCheckLatestRoundData(AggregatorV3Interface priceFeed)
        public
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            priceFeed.latestRoundData();

        uint256 secondsSince = block.timestamp - updatedAt;
        if (secondsSince > TIMEOUT) {
            revert OracleLib__StalePrice();
        }
        return (roundId, answer, startedAt, updatedAt, answeredInRound);
    }
}
