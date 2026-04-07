// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IIdentity} from "./IIdentity.sol";

/**
 * @title IIdentityRegistry
 * @notice Interface for the Identity Registry contract
 * @dev Based on ERC-3643 standard, simplified for tutorial
 * 
 * The Identity Registry is the core of the permissioned token system.
 * It maps wallet addresses to identity contracts and verifies investor eligibility.
 * 
 * Key concepts:
 * - Only verified investors can hold/receive tokens
 * - Verification can be simple (has identity) or complex (has valid claims)
 * - Agents manage the registry (KYC providers, compliance officers)
 */
interface IIdentityRegistry {
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Emitted when a new identity is registered
     * @param wallet The investor's wallet address
     * @param identity The identity contract address
     */
    event IdentityRegistered(address indexed wallet, IIdentity indexed identity);

    /**
     * @notice Emitted when an identity is updated
     * @param wallet The investor's wallet address
     * @param oldIdentity The previous identity contract
     * @param newIdentity The new identity contract
     */
    event IdentityUpdated(address indexed wallet, IIdentity indexed oldIdentity, IIdentity indexed newIdentity);

    /**
     * @notice Emitted when an identity is removed
     * @param wallet The investor's wallet address
     * @param identity The removed identity contract
     */
    event IdentityRemoved(address indexed wallet, IIdentity indexed identity);

    /**
     * @notice Emitted when an investor's country is updated
     * @param wallet The investor's wallet address
     * @param country The new country code (ISO 3166-1 numeric)
     */
    event CountryUpdated(address indexed wallet, uint16 indexed country);

    /*//////////////////////////////////////////////////////////////
                            CORE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Register a new identity in the registry
     * @param wallet The investor's wallet address
     * @param identityContract The identity contract address
     * @param country The investor's country code (ISO 3166-1 numeric, e.g., 840 = USA)
     * 
     * @dev Only callable by agents (KYC providers)
     * @dev Reverts if wallet is already registered
     */
    function registerIdentity(address wallet, IIdentity identityContract, uint16 country) external;

    /**
     * @notice Update an existing identity (e.g., investor changes KYC provider)
     * @param wallet The investor's wallet address
     * @param identityContract The new identity contract address
     * 
     * @dev Only callable by agents
     * @dev Reverts if wallet is not registered
     */
    function updateIdentity(address wallet, IIdentity identityContract) external;

    /**
     * @notice Update an investor's country code
     * @param wallet The investor's wallet address
     * @param country The new country code
     * 
     * @dev Only callable by agents
     * @dev Used when investor relocates
     */
    function updateCountry(address wallet, uint16 country) external;

    /**
     * @notice Remove an identity from the registry
     * @param wallet The investor's wallet address
     * 
     * @dev Only callable by agents
     * @dev Investor will no longer be able to receive tokens
     */
    function deleteIdentity(address wallet) external;

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Check if a wallet is verified and eligible to hold tokens
     * @param wallet The wallet address to check
     * @return verified True if the wallet is verified
     * 
     * @dev This is called by the token contract on every transfer
     * @dev Phase 1: Returns true if wallet has an identity
     * @dev Phase 2: Returns true if wallet has valid claims from trusted issuers
     */
    function isVerified(address wallet) external view returns (bool);

    /**
     * @notice Get the identity contract for a wallet
     * @param wallet The wallet address
     * @return identity The identity contract (address(0) if not registered)
     */
    function identity(address wallet) external view returns (IIdentity);

    /**
     * @notice Get the country code for an investor
     * @param wallet The wallet address
     * @return country The country code (0 if not registered)
     */
    function investorCountry(address wallet) external view returns (uint16);

    /**
     * @notice Check if a wallet is registered (has an identity)
     * @param wallet The wallet address
     * @return registered True if the wallet has an identity
     * 
     * @dev Similar to isVerified() but doesn't check claims
     */
    function contains(address wallet) external view returns (bool);
}
