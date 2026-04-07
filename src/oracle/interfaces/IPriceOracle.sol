// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

/**
 * @title IPriceOracle
 * @notice Interface for price oracle (simulates Chainlink AggregatorV3Interface)
 * @dev Provides asset prices with staleness checks
 */
interface IPriceOracle {
    /**
     * @notice Get the latest price data
     * @return roundId The round ID
     * @return answer The price (8 decimals for Chainlink compatibility)
     * @return startedAt Timestamp when round started
     * @return updatedAt Timestamp when round was updated
     * @return answeredInRound The round ID in which the answer was computed
     */
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);

    /**
     * @notice Get the number of decimals in the price
     * @return decimals Number of decimals (typically 8 for Chainlink)
     */
    function decimals() external view returns (uint8);

    /**
     * @notice Get description of what this oracle provides
     * @return description Human-readable description (e.g., "TSLA / USD")
     */
    function description() external view returns (string memory);

    /**
     * @notice Get the version of the oracle
     * @return version Version number
     */
    function version() external view returns (uint256);
}
