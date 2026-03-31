// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IClaimIssuer} from "./IClaimIssuer.sol";

/**
 * @title ITrustedIssuersRegistry
 * @notice Interface for the Trusted Issuers Registry
 * @dev Defines which entities can issue valid claims for this token
 * 
 * Trusted issuers are KYC providers, regulators, or other authorities
 * who can attest to investor eligibility.
 * 
 * This registry is OPTIONAL in Phase 1 of the tutorial.
 * When set, the IdentityRegistry will only accept claims from trusted issuers.
 */
interface ITrustedIssuersRegistry {
    /**
     * @notice Get all trusted issuers for a specific claim topic
     * @param claimTopic The claim topic ID
     * @return issuers Array of trusted claim issuers
     * 
     * @dev Called by IdentityRegistry during claim verification
     */
    function getTrustedIssuersForClaimTopic(uint256 claimTopic) external view returns (IClaimIssuer[] memory);

    /**
     * @notice Check if an issuer is trusted for a specific claim topic
     * @param issuer The issuer address
     * @param claimTopic The claim topic ID
     * @return trusted True if the issuer is trusted for this topic
     */
    function isTrustedIssuer(address issuer, uint256 claimTopic) external view returns (bool);

    /**
     * @notice Add a trusted issuer
     * @param issuer The issuer to add
     * @param claimTopics Array of claim topics this issuer can attest to
     * 
     * @dev Only callable by owner
     */
    function addTrustedIssuer(IClaimIssuer issuer, uint256[] calldata claimTopics) external;

    /**
     * @notice Remove a trusted issuer
     * @param issuer The issuer to remove
     * 
     * @dev Only callable by owner
     */
    function removeTrustedIssuer(IClaimIssuer issuer) external;
}
