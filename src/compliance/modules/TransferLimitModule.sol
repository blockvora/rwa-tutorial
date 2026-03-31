// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {AbstractModule} from "./AbstractModule.sol";

/**
 * @title TransferLimitModule
 * @notice Compliance module that limits transfer volume per time period
 * @dev Example of a TIME-BASED STATEFUL module
 * 
 * PATTERN: Time-windowed accounting
 * 
 * Rule: No identity can transfer more than dailyLimit tokens per day
 * 
 * How it works:
 * 1. moduleCheck() verifies sender's daily volume + amount <= dailyLimit
 * 2. moduleTransferAction() increments sender's daily counter
 * 3. Counters reset automatically each day (via timestamp)
 * 
 * Why daily limits?
 * - Prevent rapid liquidation (market manipulation)
 * - Comply with Reg D restrictions (limited resale)
 * - Detect suspicious activity (large sudden transfers)
 * 
 * Use case: Reg D Rule 144 restrictions, anti-manipulation, AML compliance
 */
contract TransferLimitModule is AbstractModule {
    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice Daily transfer limit per identity
    uint256 public dailyLimit;

    /// @notice Transfer volume per identity per day
    /// @dev identity => day (timestamp / 1 days) => volume
    mapping(address => mapping(uint256 => uint256)) public dailyTransferVolume;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Emitted when daily limit is updated
     * @param oldLimit The previous daily limit
     * @param newLimit The new daily limit
     */
    event DailyLimitSet(uint256 oldLimit, uint256 newLimit);

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initialize the module
     * @param identityRegistry The identity registry contract address
     * @param _dailyLimit The daily transfer limit per identity
     */
    constructor(address identityRegistry, uint256 _dailyLimit) AbstractModule(identityRegistry) {
        require(_dailyLimit > 0, "TransferLimitModule: daily limit must be positive");
        dailyLimit = _dailyLimit;
    }

    /*//////////////////////////////////////////////////////////////
                          COMPLIANCE CHECKS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Check if transfer would exceed daily limit for sender
     * @param from The sender address
     * @param to The receiver address (not checked by this module)
     * @param amount The transfer amount
     * @param compliance The compliance contract (not used)
     * @return compliant True if sender's daily volume + amount <= dailyLimit
     * 
     * @dev Only checks SENDER (not receiver)
     * @dev Uses identity (not wallet) to prevent multi-wallet circumvention
     * @dev Day is calculated as: block.timestamp / 1 days
     */
    function moduleCheck(address from, address to, uint256 amount, address compliance)
        external
        view
        override
        returns (bool)
    {
        // Get sender's identity
        address fromIdentity = _getIdentity(from);

        // If identity not registered, let IdentityRegistry handle it
        if (fromIdentity == address(0)) {
            return true;
        }

        // Calculate current day (resets at midnight UTC)
        uint256 today = block.timestamp / 1 days;

        // Get current daily volume for sender
        uint256 currentVolume = dailyTransferVolume[fromIdentity][today];

        // Check if adding this transfer would exceed limit
        if (currentVolume + amount > dailyLimit) {
            return false;
        }

        return true;
    }

    /*//////////////////////////////////////////////////////////////
                          STATE UPDATES
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Update sender's daily transfer volume
     * @param from The sender address
     * @param to The receiver address (not used)
     * @param amount The transfer amount
     * 
     * @dev Increments sender's counter for today
     * @dev Counter automatically resets when day changes (new timestamp / 1 days)
     * @dev Safety check ensures limit not exceeded
     */
    function moduleTransferAction(address from, address to, uint256 amount)
        external
        override
        onlyBoundCompliance
    {
        address fromIdentity = _getIdentity(from);
        uint256 today = block.timestamp / 1 days;

        // Increment daily volume
        dailyTransferVolume[fromIdentity][today] += amount;

        // Safety check: ensure limit not exceeded
        require(
            dailyTransferVolume[fromIdentity][today] <= dailyLimit,
            "TransferLimitModule: daily limit exceeded"
        );
    }

    /**
     * @notice No state to update on mint
     * @dev Minting doesn't count toward transfer limits
     */
    function moduleMintAction(address to, uint256 amount) external override onlyBoundCompliance {
        // No-op: Minting doesn't count as transfer
    }

    /**
     * @notice Update sender's daily volume on burn
     * @param from The sender address
     * @param amount The burn amount
     * 
     * @dev Burning counts as a transfer (prevents limit circumvention via burn/mint)
     */
    function moduleBurnAction(address from, uint256 amount) external override onlyBoundCompliance {
        address fromIdentity = _getIdentity(from);
        uint256 today = block.timestamp / 1 days;

        // Increment daily volume (burning counts as transfer)
        dailyTransferVolume[fromIdentity][today] += amount;

        // Safety check
        require(
            dailyTransferVolume[fromIdentity][today] <= dailyLimit,
            "TransferLimitModule: daily limit exceeded"
        );
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get the module name
     * @return name The module identifier
     */
    function name() external pure override returns (string memory) {
        return "TransferLimitModule";
    }

    /**
     * @notice Get remaining transfer capacity for today
     * @param wallet The wallet address
     * @return remaining The amount that can still be transferred today
     */
    function getRemainingDailyLimit(address wallet) external view returns (uint256) {
        address identity = _getIdentity(wallet);
        uint256 today = block.timestamp / 1 days;
        uint256 used = dailyTransferVolume[identity][today];

        if (used >= dailyLimit) {
            return 0;
        }

        return dailyLimit - used;
    }

    /**
     * @notice Get daily volume used for a specific day
     * @param wallet The wallet address
     * @param day The day to check (timestamp / 1 days)
     * @return volume The volume transferred on that day
     */
    function getDailyVolume(address wallet, uint256 day) external view returns (uint256) {
        address identity = _getIdentity(wallet);
        return dailyTransferVolume[identity][day];
    }

    /**
     * @notice Get today's volume for a wallet
     * @param wallet The wallet address
     * @return volume The volume transferred today
     */
    function getTodayVolume(address wallet) external view returns (uint256) {
        address identity = _getIdentity(wallet);
        uint256 today = block.timestamp / 1 days;
        return dailyTransferVolume[identity][today];
    }

    /*//////////////////////////////////////////////////////////////
                          ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Update the daily transfer limit
     * @param _dailyLimit The new daily limit
     * 
     * @dev Only callable by owner
     * @dev Can be used to adjust limits as regulations change
     */
    function setDailyLimit(uint256 _dailyLimit) external onlyOwner {
        require(_dailyLimit > 0, "TransferLimitModule: daily limit must be positive");

        uint256 oldLimit = dailyLimit;
        dailyLimit = _dailyLimit;

        emit DailyLimitSet(oldLimit, _dailyLimit);
    }
}
