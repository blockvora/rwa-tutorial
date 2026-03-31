// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IIdentity} from "./IIdentity.sol";

/**
 * @title IClaimIssuer
 * @notice Interface for entities that can issue claims
 * @dev Claim issuers are typically KYC providers or regulatory authorities
 * 
 * A claim issuer:
 * - Has its own identity contract
 * - Can sign claims about investors
 * - Validates that claims are still valid (not revoked)
 */
interface IClaimIssuer is IIdentity {
    /**
     * @notice Check if a claim is valid
     * @param identity The identity contract of the claim holder
     * @param claimTopic The topic of the claim to verify
     * @param signature The signature on the claim
     * @param data The claim data
     * @return valid True if the claim is valid and not revoked
     * 
     * @dev Called by IdentityRegistry during verification
     */
    function isClaimValid(IIdentity identity, uint256 claimTopic, bytes memory signature, bytes memory data)
        external
        view
        returns (bool);

    /**
     * @notice Revoke a previously issued claim
     * @param signature The signature to revoke
     * 
     * @dev Only callable by the issuer
     * @dev Used when investor loses eligibility
     */
    function revokeClaimBySignature(bytes memory signature) external;
}
