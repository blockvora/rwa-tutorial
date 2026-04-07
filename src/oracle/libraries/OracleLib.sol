// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IPriceOracle} from "../interfaces/IPriceOracle.sol";

/**
 * @title OracleLib
 * @notice Library for oracle data validation and price conversions
 * @dev Based on rwa-creator patterns, adapted for tutorial use
 * 
 * This library provides:
 * - Stale price detection
 * - Price conversion utilities
 * - Decimal handling
 */
library OracleLib {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error OracleLib__StalePrice();
    error OracleLib__InvalidPrice();
    error OracleLib__InvalidRoundData();

    /*//////////////////////////////////////////////////////////////
                               CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Maximum age of price data before considered stale
    /// @dev In production, this should be configurable per asset
    uint256 private constant TIMEOUT = 3 hours;

    /// @notice Additional precision for price calculations
    /// @dev Chainlink feeds use 8 decimals, we often need 18
    uint256 public constant ADDITIONAL_FEED_PRECISION = 1e10;

    /// @notice Standard precision for calculations
    uint256 public constant PRECISION = 1e18;

    /*//////////////////////////////////////////////////////////////
                           STALENESS CHECKS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get latest round data with staleness checks
     * @param priceFeed The price feed to query
     * @return roundId The round ID
     * @return answer The price
     * @return startedAt When the round started
     * @return updatedAt When the round was updated
     * @return answeredInRound The round in which answer was computed
     * 
     * @dev Reverts if:
     * - Price data is stale (older than TIMEOUT)
     * - Round data is invalid (answeredInRound < roundId)
     * - Price is zero or negative
     */
    function staleCheckLatestRoundData(IPriceOracle priceFeed)
        internal
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            priceFeed.latestRoundData();

        // Check for invalid round data
        if (updatedAt == 0 || answeredInRound < roundId) {
            revert OracleLib__InvalidRoundData();
        }

        // Check for stale price
        uint256 secondsSince = block.timestamp - updatedAt;
        if (secondsSince > TIMEOUT) {
            revert OracleLib__StalePrice();
        }

        // Check for invalid price
        if (answer <= 0) {
            revert OracleLib__InvalidPrice();
        }

        return (roundId, answer, startedAt, updatedAt, answeredInRound);
    }

    /**
     * @notice Get the timeout threshold
     * @return timeout The staleness timeout in seconds
     */
    function getTimeout() internal pure returns (uint256) {
        return TIMEOUT;
    }

    /*//////////////////////////////////////////////////////////////
                          PRICE CONVERSIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Convert token amount to USD value
     * @param priceFeed The price feed for the token
     * @param tokenAmount The amount of tokens (18 decimals)
     * @return usdValue The USD value (18 decimals)
     * 
     * @dev Assumes token has 18 decimals, price feed has 8 decimals
     * @dev Formula: (tokenAmount * price * 1e10) / 1e18
     */
    function getUsdValue(IPriceOracle priceFeed, uint256 tokenAmount) internal view returns (uint256) {
        (, int256 price,,,) = staleCheckLatestRoundData(priceFeed);
        // price has 8 decimals, multiply by 1e10 to get 18 decimals
        // tokenAmount has 18 decimals
        // Result: (18 decimals * 18 decimals) / 18 decimals = 18 decimals
        
        // Safe cast: Chainlink price feeds return positive prices, checked in staleCheckLatestRoundData
        return (tokenAmount * uint256(price) * ADDITIONAL_FEED_PRECISION) / PRECISION;
    }

    /**
     * @notice Convert USD value to token amount
     * @param priceFeed The price feed for the token
     * @param usdAmount The USD amount (18 decimals)
     * @return tokenAmount The token amount (18 decimals)
     * 
     * @dev Assumes token has 18 decimals, price feed has 8 decimals
     * @dev Formula: (usdAmount * 1e18) / (price * 1e10)
     */
    function getTokenAmount(IPriceOracle priceFeed, uint256 usdAmount) internal view returns (uint256) {
        (, int256 price,,,) = staleCheckLatestRoundData(priceFeed);
        // usdAmount has 18 decimals
        // price has 8 decimals, multiply by 1e10 to get 18 decimals
        // Result: (18 decimals * 18 decimals) / 18 decimals = 18 decimals
        
        // Safe cast: Chainlink price feeds return positive prices, checked in staleCheckLatestRoundData
        return (usdAmount * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION);
    }

    /**
     * @notice Get the current price from a feed
     * @param priceFeed The price feed to query
     * @return price The current price (18 decimals)
     * 
     * @dev Converts 8-decimal Chainlink price to 18 decimals
     */
    function getPrice(IPriceOracle priceFeed) internal view returns (uint256) {
        (, int256 price,,,) = staleCheckLatestRoundData(priceFeed);
        
        // Safe cast: Chainlink price feeds return positive prices, checked in staleCheckLatestRoundData
        return uint256(price) * ADDITIONAL_FEED_PRECISION;
    }

    /**
     * @notice Get the raw price from a feed without staleness check
     * @param priceFeed The price feed to query
     * @return price The current price (8 decimals, as returned by Chainlink)
     * 
     * @dev Use with caution - does not check staleness
     * @dev Useful for view functions where revert is not desired
     */
    function getRawPrice(IPriceOracle priceFeed) internal view returns (int256) {
        (, int256 price,,,) = priceFeed.latestRoundData();
        return price;
    }
}
