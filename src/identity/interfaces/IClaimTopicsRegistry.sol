// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

/**
 * @title IClaimTopicsRegistry
 * @notice Interface for the Claim Topics Registry
 * @dev Defines which claim types are required for token holders
 * 
 * Claim topics are standardized numbers representing different attestations:
 * - 1: KYC verification
 * - 2: Accredited investor status
 * - 3: Country verification
 * - etc.
 * 
 * This registry is OPTIONAL in Phase 1 of the tutorial.
 * When set, the IdentityRegistry will verify investors have all required claims.
 */
interface IClaimTopicsRegistry {
    /**
     * @notice Get all required claim topics for this token
     * @return topics Array of claim topic IDs
     * 
     * @dev Called by IdentityRegistry during verification
     */
    function getClaimTopics() external view returns (uint256[] memory);

    /**
     * @notice Add a required claim topic
     * @param claimTopic The topic ID to add
     * 
     * @dev Only callable by owner
     */
    function addClaimTopic(uint256 claimTopic) external;

    /**
     * @notice Remove a claim topic
     * @param claimTopic The topic ID to remove
     * 
     * @dev Only callable by owner
     */
    function removeClaimTopic(uint256 claimTopic) external;
}
