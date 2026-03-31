// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

/**
 * @title IIdentity
 * @notice Minimal interface for ONCHAINID identity contracts
 * @dev Based on ERC-3643 / ONCHAINID standard
 * 
 * An identity contract stores claims about an investor:
 * - KYC verification status
 * - Accredited investor status
 * - Country of residence
 * - Other regulatory attestations
 * 
 * Claims are signed by trusted issuers (KYC providers, regulators, etc.)
 */
interface IIdentity {
    /**
     * @notice Get a claim from the identity contract
     * @param claimId Unique identifier for the claim (hash of issuer + topic)
     * @return topic The claim topic (e.g., 1 = KYC, 2 = Accreditation)
     * @return scheme The signature scheme used (e.g., 1 = ECDSA)
     * @return issuer Address of the claim issuer
     * @return signature The issuer's signature on the claim data
     * @return data The actual claim data (ABI-encoded)
     * @return uri Optional URI for additional claim information
     * 
     * @dev Returns empty values if claim doesn't exist
     */
    function getClaim(bytes32 claimId)
        external
        view
        returns (uint256 topic, uint256 scheme, address issuer, bytes memory signature, bytes memory data, string memory uri);

    /**
     * @notice Check if a key has a specific purpose
     * @param key The key to check
     * @param purpose The purpose to verify (1 = MANAGEMENT, 2 = ACTION, 3 = CLAIM, 4 = ENCRYPTION)
     * @return exists True if the key has the specified purpose
     * 
     * @dev Used to verify that a wallet address is authorized for this identity
     */
    function keyHasPurpose(bytes32 key, uint256 purpose) external view returns (bool exists);
}
