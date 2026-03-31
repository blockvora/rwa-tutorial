// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IIdentityRegistry} from "./interfaces/IIdentityRegistry.sol";
import {IIdentity} from "./interfaces/IIdentity.sol";
import {IClaimTopicsRegistry} from "./interfaces/IClaimTopicsRegistry.sol";
import {ITrustedIssuersRegistry} from "./interfaces/ITrustedIssuersRegistry.sol";
import {IClaimIssuer} from "./interfaces/IClaimIssuer.sol";

/**
 * @title IdentityRegistry
 * @notice Manages investor identities and verification for permissioned tokens
 * @dev Simplified ERC-3643 implementation for tutorial purposes
 * 
 * TUTORIAL PROGRESSION:
 * 
 * Phase 1 (Basic): 
 * - Register identities (wallet → identity contract mapping)
 * - Simple verification: has identity = verified
 * - No claim checking yet
 * 
 * Phase 2 (Advanced):
 * - Set ClaimTopicsRegistry (what claims are required?)
 * - Set TrustedIssuersRegistry (who can issue claims?)
 * - Complex verification: check all required claims are valid
 * 
 * SECURITY MODEL:
 * - Agents: Can register/update/delete identities (KYC providers)
 * - Admin: Can add/remove agents, set registries (token owner)
 * - Public: Can query verification status (read-only)
 */
contract IdentityRegistry is IIdentityRegistry, AccessControl {
    /*//////////////////////////////////////////////////////////////
                                 ROLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Role for agents who can manage identities
    bytes32 public constant AGENT_ROLE = keccak256("AGENT_ROLE");

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice Maps wallet addresses to their identity contracts
    mapping(address => IIdentity) private _identities;

    /// @notice Maps wallet addresses to their country codes (ISO 3166-1 numeric)
    mapping(address => uint16) private _investorCountry;

    /// @notice Registry of required claim topics (optional, for Phase 2)
    IClaimTopicsRegistry private _claimTopicsRegistry;

    /// @notice Registry of trusted claim issuers (optional, for Phase 2)
    ITrustedIssuersRegistry private _trustedIssuersRegistry;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initialize the registry and grant roles to deployer
     * @dev Deployer becomes both admin and first agent
     */
    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(AGENT_ROLE, msg.sender);
    }

    /*//////////////////////////////////////////////////////////////
                            CORE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Register a new identity in the registry
     * @param wallet The investor's wallet address
     * @param identity The identity contract address
     * @param country The investor's country code (e.g., 840 = USA)
     * 
     * @dev Only callable by agents
     * @dev Reverts if wallet is zero address, identity is zero, or wallet already registered
     */
    function registerIdentity(address wallet, IIdentity identity, uint16 country)
        external
        override
        onlyRole(AGENT_ROLE)
    {
        require(wallet != address(0), "IdentityRegistry: invalid wallet address");
        require(address(identity) != address(0), "IdentityRegistry: invalid identity address");
        require(address(_identities[wallet]) == address(0), "IdentityRegistry: identity already registered");

        _identities[wallet] = identity;
        _investorCountry[wallet] = country;

        emit IdentityRegistered(wallet, identity);
    }

    /**
     * @notice Update an existing identity (e.g., investor changes KYC provider)
     * @param wallet The investor's wallet address
     * @param identity The new identity contract address
     * 
     * @dev Only callable by agents
     * @dev Reverts if wallet is not registered or new identity is invalid
     */
    function updateIdentity(address wallet, IIdentity identity) external override onlyRole(AGENT_ROLE) {
        require(address(identity) != address(0), "IdentityRegistry: invalid identity address");
        IIdentity oldIdentity = _identities[wallet];
        require(address(oldIdentity) != address(0), "IdentityRegistry: identity not registered");

        _identities[wallet] = identity;

        emit IdentityUpdated(wallet, oldIdentity, identity);
    }

    /**
     * @notice Update an investor's country code
     * @param wallet The investor's wallet address
     * @param country The new country code
     * 
     * @dev Only callable by agents
     * @dev Used when investor relocates
     */
    function updateCountry(address wallet, uint16 country) external override onlyRole(AGENT_ROLE) {
        require(address(_identities[wallet]) != address(0), "IdentityRegistry: identity not registered");

        _investorCountry[wallet] = country;

        emit CountryUpdated(wallet, country);
    }

    /**
     * @notice Remove an identity from the registry
     * @param wallet The investor's wallet address
     * 
     * @dev Only callable by agents
     * @dev Investor will no longer pass verification checks
     */
    function deleteIdentity(address wallet) external override onlyRole(AGENT_ROLE) {
        IIdentity oldIdentity = _identities[wallet];
        require(address(oldIdentity) != address(0), "IdentityRegistry: identity not registered");

        delete _identities[wallet];
        delete _investorCountry[wallet];

        emit IdentityRemoved(wallet, oldIdentity);
    }

    /*//////////////////////////////////////////////////////////////
                          VERIFICATION LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Check if a wallet is verified and eligible to hold tokens
     * @param wallet The wallet address to check
     * @return verified True if the wallet is verified
     * 
     * @dev PHASE 1: Returns true if wallet has an identity
     * @dev PHASE 2: If claim registries are set, verifies all required claims
     * 
     * This function is called by the token contract on EVERY transfer.
     * It must be gas-efficient and accurate.
     */
    function isVerified(address wallet) external view override returns (bool) {
        // Step 1: Check if identity exists
        IIdentity investorIdentity = _identities[wallet];
        if (address(investorIdentity) == address(0)) {
            return false;
        }

        // Step 2: If no claim requirements, registration is sufficient (Phase 1)
        if (address(_claimTopicsRegistry) == address(0)) {
            return true;
        }

        // Step 3: Verify all required claims (Phase 2)
        uint256[] memory requiredClaimTopics = _claimTopicsRegistry.getClaimTopics();

        // If no topics required, registration is sufficient
        if (requiredClaimTopics.length == 0) {
            return true;
        }

        // Check each required claim topic
        for (uint256 i = 0; i < requiredClaimTopics.length; i++) {
            if (!_hasValidClaim(investorIdentity, requiredClaimTopics[i])) {
                return false;
            }
        }

        return true;
    }

    /**
     * @notice Check if an identity has a valid claim for a specific topic
     * @param investorIdentity The identity contract to check
     * @param claimTopic The claim topic to verify
     * @return valid True if a valid claim exists
     * 
     * @dev Internal helper for claim verification
     * @dev Checks that:
     *      1. At least one trusted issuer exists for this topic
     *      2. The identity has a claim from a trusted issuer
     *      3. The claim is valid (not revoked)
     */
    function _hasValidClaim(IIdentity investorIdentity, uint256 claimTopic) internal view returns (bool) {
        // Get trusted issuers for this claim topic
        if (address(_trustedIssuersRegistry) == address(0)) {
            return false;
        }

        IClaimIssuer[] memory trustedIssuers = _trustedIssuersRegistry.getTrustedIssuersForClaimTopic(claimTopic);

        // Must have at least one trusted issuer
        if (trustedIssuers.length == 0) {
            return false;
        }

        // Check if identity has a valid claim from any trusted issuer
        for (uint256 i = 0; i < trustedIssuers.length; i++) {
            bytes32 claimId = keccak256(abi.encode(address(trustedIssuers[i]), claimTopic));

            // Query the claim from the identity contract
            (uint256 foundTopic, uint256 scheme, address issuer, bytes memory signature, bytes memory data,) =
                investorIdentity.getClaim(claimId);

            // Check if claim exists and matches the topic
            if (foundTopic == claimTopic) {
                // Verify the claim is still valid (not revoked)
                try trustedIssuers[i].isClaimValid(investorIdentity, claimTopic, signature, data) returns (
                    bool isValid
                ) {
                    if (isValid) {
                        return true; // Found a valid claim
                    }
                } catch {
                    // Issuer contract call failed, try next issuer
                    continue;
                }
            }
        }

        // No valid claim found from any trusted issuer
        return false;
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get the identity contract for a wallet
     * @param wallet The wallet address
     * @return identity The identity contract (address(0) if not registered)
     */
    function identity(address wallet) external view override returns (IIdentity) {
        return _identities[wallet];
    }

    /**
     * @notice Get the country code for an investor
     * @param wallet The wallet address
     * @return country The country code (0 if not registered)
     */
    function investorCountry(address wallet) external view override returns (uint16) {
        return _investorCountry[wallet];
    }

    /**
     * @notice Check if a wallet is registered (has an identity)
     * @param wallet The wallet address
     * @return registered True if the wallet has an identity
     */
    function contains(address wallet) external view override returns (bool) {
        return address(_identities[wallet]) != address(0);
    }

    /**
     * @notice Get the claim topics registry address
     * @return registry The claim topics registry (address(0) if not set)
     */
    function claimTopicsRegistry() external view returns (IClaimTopicsRegistry) {
        return _claimTopicsRegistry;
    }

    /**
     * @notice Get the trusted issuers registry address
     * @return registry The trusted issuers registry (address(0) if not set)
     */
    function trustedIssuersRegistry() external view returns (ITrustedIssuersRegistry) {
        return _trustedIssuersRegistry;
    }

    /*//////////////////////////////////////////////////////////////
                          ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Set the claim topics registry (Phase 2)
     * @param registry The claim topics registry address
     * 
     * @dev Only callable by admin
     * @dev Once set, isVerified() will check claims
     */
    function setClaimTopicsRegistry(address registry) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _claimTopicsRegistry = IClaimTopicsRegistry(registry);
    }

    /**
     * @notice Set the trusted issuers registry (Phase 2)
     * @param registry The trusted issuers registry address
     * 
     * @dev Only callable by admin
     * @dev Required for claim verification to work
     */
    function setTrustedIssuersRegistry(address registry) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _trustedIssuersRegistry = ITrustedIssuersRegistry(registry);
    }
}
