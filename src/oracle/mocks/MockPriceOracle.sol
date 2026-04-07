// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IPriceOracle} from "../interfaces/IPriceOracle.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title MockPriceOracle
 * @notice Mock implementation of Chainlink AggregatorV3Interface for testing
 * @dev Simulates Chainlink price feeds with manual price updates
 * 
 * In production, replace with real Chainlink Price Feeds:
 * - TSLA/USD: https://data.chain.link/feeds/ethereum/mainnet/tsla-usd
 * - USDC/USD: https://data.chain.link/feeds/ethereum/mainnet/usdc-usd
 * 
 * This mock allows:
 * - Manual price updates for testing
 * - Simulation of stale data
 * - Deterministic test scenarios
 */
contract MockPriceOracle is IPriceOracle, Ownable {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error MockPriceOracle__InvalidPrice();

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Current round ID
    uint80 private s_roundId;

    /// @notice Current price (8 decimals to match Chainlink)
    int256 private s_answer;

    /// @notice When the current round started
    uint256 private s_startedAt;

    /// @notice When the price was last updated
    uint256 private s_updatedAt;

    /// @notice Round ID in which answer was computed
    uint80 private s_answeredInRound;

    /// @notice Number of decimals (8 for Chainlink compatibility)
    uint8 private constant DECIMALS = 8;

    /// @notice Description of this price feed
    string private s_description;

    /// @notice Version of the oracle
    uint256 private constant VERSION = 1;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event PriceUpdated(uint80 indexed roundId, int256 price, uint256 timestamp);

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initialize the mock price oracle
     * @param initialPrice The initial price (8 decimals)
     * @param description_ Description of the feed (e.g., "TSLA / USD")
     */
    constructor(int256 initialPrice, string memory description_) Ownable(msg.sender) {
        require(initialPrice > 0, "MockPriceOracle: invalid initial price");

        s_description = description_;
        _updatePrice(initialPrice);
    }

    /*//////////////////////////////////////////////////////////////
                           ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Update the price (for testing)
     * @param newPrice The new price (8 decimals)
     * 
     * @dev Only owner can update price
     * @dev In production, Chainlink nodes update prices automatically
     */
    function updatePrice(int256 newPrice) external onlyOwner {
        require(newPrice > 0, "MockPriceOracle: invalid price");
        _updatePrice(newPrice);
    }

    /**
     * @dev Internal function to update price and round data
     */
    function _updatePrice(int256 newPrice) private {
        s_roundId++;
        s_answer = newPrice;
        s_startedAt = block.timestamp;
        s_updatedAt = block.timestamp;
        s_answeredInRound = s_roundId;

        emit PriceUpdated(s_roundId, newPrice, block.timestamp);
    }

    /**
     * @notice Simulate stale data by setting old timestamp
     * @param timestamp The timestamp to set (for testing staleness)
     * 
     * @dev Only for testing - allows simulation of stale oracle data
     */
    function setUpdatedAt(uint256 timestamp) external onlyOwner {
        s_updatedAt = timestamp;
    }

    /*//////////////////////////////////////////////////////////////
                          ORACLE INTERFACE
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IPriceOracle
     */
    function latestRoundData()
        external
        view
        override
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (s_roundId, s_answer, s_startedAt, s_updatedAt, s_answeredInRound);
    }

    /**
     * @inheritdoc IPriceOracle
     */
    function decimals() external pure override returns (uint8) {
        return DECIMALS;
    }

    /**
     * @inheritdoc IPriceOracle
     */
    function description() external view override returns (string memory) {
        return s_description;
    }

    /**
     * @inheritdoc IPriceOracle
     */
    function version() external pure override returns (uint256) {
        return VERSION;
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get the current price in human-readable format
     * @return price The current price (8 decimals)
     */
    function getPrice() external view returns (int256) {
        return s_answer;
    }

    /**
     * @notice Check if the price data is stale
     * @param stalenessThreshold Maximum age in seconds
     * @return isStale Whether the data is stale
     */
    function isStale(uint256 stalenessThreshold) external view returns (bool) {
        return block.timestamp - s_updatedAt > stalenessThreshold;
    }
}
