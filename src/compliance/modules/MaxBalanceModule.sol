// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {AbstractModule} from "./AbstractModule.sol";

/**
 * @title MaxBalanceModule
 * @notice Compliance module that limits token balance per identity
 * @dev Example of a STATEFUL module (tracks balances per identity)
 * 
 * PATTERN: Identity-based accounting
 * 
 * Rule: No identity can hold more than maxBalance tokens
 * 
 * How it works:
 * 1. moduleCheck() verifies receiver's balance + amount <= maxBalance
 * 2. moduleTransferAction() updates sender and receiver balances
 * 3. Balances are tracked per IDENTITY (not per wallet)
 * 
 * Why per identity?
 * - One person can have multiple wallets
 * - Compliance rules apply to the person, not the wallet
 * - Prevents circumventing limits by using multiple addresses
 * 
 * Use case: Prevent concentration of ownership, comply with shareholder limits
 */
contract MaxBalanceModule is AbstractModule {
    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice Maximum balance allowed per identity
    uint256 public maxBalance;

    /// @notice Balance per identity (identity address => balance)
    /// @dev Tracks tokens held by each ONCHAINID, not by wallet
    mapping(address => uint256) public identityBalance;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Emitted when max balance is updated
     * @param oldMax The previous max balance
     * @param newMax The new max balance
     */
    event MaxBalanceSet(uint256 oldMax, uint256 newMax);

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initialize the module
     * @param identityRegistry The identity registry contract address
     * @param _maxBalance The maximum balance per identity
     */
    constructor(address identityRegistry, uint256 _maxBalance) AbstractModule(identityRegistry) {
        require(_maxBalance > 0, "MaxBalanceModule: max balance must be positive");
        maxBalance = _maxBalance;
    }

    /*//////////////////////////////////////////////////////////////
                          COMPLIANCE CHECKS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Check if transfer would exceed max balance for receiver
     * @param from The sender address
     * @param to The receiver address
     * @param amount The transfer amount
     * @param compliance The compliance contract (not used)
     * @return compliant True if receiver's balance + amount <= maxBalance
     * 
     * @dev Checks BOTH sender and receiver identities
     * @dev Prevents single transfer from exceeding max
     * @dev Also prevents transferring more than sender has (defensive check)
     */
    function moduleCheck(address from, address to, uint256 amount, address compliance)
        external
        view
        override
        returns (bool)
    {
        // Get identities for both parties
        address fromIdentity = _getIdentity(from);
        address toIdentity = _getIdentity(to);

        // If either identity is not registered, let IdentityRegistry handle it
        // This module only checks balance limits
        if (fromIdentity == address(0) || toIdentity == address(0)) {
            return true; // Let other checks handle identity verification
        }

        // Check if single transfer amount exceeds max (prevent large transfers)
        if (amount > maxBalance) {
            return false;
        }

        // Check if receiver would exceed max balance
        if (identityBalance[toIdentity] + amount > maxBalance) {
            return false;
        }

        // Check if sender has sufficient balance (defensive check)
        // Note: Token contract also checks this, but good to verify here
        if (identityBalance[fromIdentity] < amount) {
            return false;
        }

        return true;
    }

    /*//////////////////////////////////////////////////////////////
                          STATE UPDATES
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Update identity balances after transfer
     * @param from The sender address
     * @param to The receiver address
     * @param amount The transfer amount
     * 
     * @dev Updates balances for IDENTITIES, not wallets
     * @dev If one person transfers between their own wallets, balance stays same
     * @dev Reverts if post-transfer balance exceeds max (safety check)
     */
    function moduleTransferAction(address from, address to, uint256 amount)
        external
        override
        onlyBoundCompliance
    {
        address fromIdentity = _getIdentity(from);
        address toIdentity = _getIdentity(to);

        // Update balances
        identityBalance[fromIdentity] -= amount;
        identityBalance[toIdentity] += amount;

        // Safety check: ensure receiver didn't exceed max
        require(identityBalance[toIdentity] <= maxBalance, "MaxBalanceModule: balance exceeds maximum");
    }

    /**
     * @notice Update identity balance after mint
     * @param to The receiver address
     * @param amount The mint amount
     * 
     * @dev Increases receiver's identity balance
     */
    function moduleMintAction(address to, uint256 amount) external override onlyBoundCompliance {
        address toIdentity = _getIdentity(to);

        identityBalance[toIdentity] += amount;

        // Safety check: ensure receiver didn't exceed max
        require(identityBalance[toIdentity] <= maxBalance, "MaxBalanceModule: balance exceeds maximum");
    }

    /**
     * @notice Update identity balance after burn
     * @param from The sender address
     * @param amount The burn amount
     * 
     * @dev Decreases sender's identity balance
     */
    function moduleBurnAction(address from, uint256 amount) external override onlyBoundCompliance {
        address fromIdentity = _getIdentity(from);

        identityBalance[fromIdentity] -= amount;
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get the module name
     * @return name The module identifier
     */
    function name() external pure override returns (string memory) {
        return "MaxBalanceModule";
    }

    /**
     * @notice Get the balance for an identity
     * @param identity The identity contract address
     * @return balance The token balance for this identity
     */
    function getIdentityBalance(address identity) external view returns (uint256) {
        return identityBalance[identity];
    }

    /**
     * @notice Get the balance for a wallet (via its identity)
     * @param wallet The wallet address
     * @return balance The token balance for this wallet's identity
     */
    function getWalletBalance(address wallet) external view returns (uint256) {
        address identity = _getIdentity(wallet);
        return identityBalance[identity];
    }

    /*//////////////////////////////////////////////////////////////
                          ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Update the maximum balance per identity
     * @param _maxBalance The new maximum balance
     * 
     * @dev Only callable by owner
     * @dev Can be used to adjust limits as regulations change
     */
    function setMaxBalance(uint256 _maxBalance) external onlyOwner {
        require(_maxBalance > 0, "MaxBalanceModule: max balance must be positive");

        uint256 oldMax = maxBalance;
        maxBalance = _maxBalance;

        emit MaxBalanceSet(oldMax, _maxBalance);
    }
}
