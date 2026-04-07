// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {AbstractModule} from "./AbstractModule.sol";

/**
 * @title AccreditedInvestorModule
 * @notice Compliance module that requires receivers to be accredited investors
 * @dev Example of a STATELESS module (no state updates needed)
 * 
 * PATTERN: Claim-based verification
 * 
 * Rule: Only accredited investors can receive tokens
 * 
 * How it works:
 * 1. moduleCheck() verifies receiver has ACCREDITED_INVESTOR claim
 * 2. Claim must be from a trusted issuer (checked by IdentityRegistry)
 * 3. No state to update (stateless module)
 * 
 * Use case: Reg D securities, private placements
 * 
 * NOTE: This module checks claims through IdentityRegistry.
 * In Phase 1 (simple verification), this will always pass if receiver is registered.
 * In Phase 2 (claim verification), this will check for actual accreditation claims.
 */
contract AccreditedInvestorModule is AbstractModule {
    /*//////////////////////////////////////////////////////////////
                               CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Claim topic for accredited investor status
    /// @dev Standard claim topic ID (can be customized)
    uint256 public constant ACCREDITED_INVESTOR_CLAIM_TOPIC = 2;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initialize the module
     * @param identityRegistry The identity registry contract address
     */
    constructor(address identityRegistry) AbstractModule(identityRegistry) {}

    /*//////////////////////////////////////////////////////////////
                          COMPLIANCE CHECKS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Check if receiver is an accredited investor
     * @param to The receiver address (must be accredited)
     * @return compliant True if receiver is accredited (or verified in Phase 1)
     * 
     * @dev This module only checks the RECEIVER
     * @dev Sender can be anyone (accredited or not)
     * @dev Amount doesn't matter for accreditation
     * @dev Sender, amount, and compliance parameters unused but required by interface
     * 
     * PHASE 1 BEHAVIOR:
     * - If IdentityRegistry has no claim requirements, this passes for all verified investors
     * 
     * PHASE 2 BEHAVIOR:
     * - IdentityRegistry checks if receiver has ACCREDITED_INVESTOR claim
     * - Claim must be from trusted issuer
     * - Claim must not be revoked
     */
    function moduleCheck(address /* from */, address to, uint256 /* amount */, address /* compliance */)
        external
        view
        override
        returns (bool)
    {
        // Check if receiver is verified (includes claim checks if configured)
        // In Phase 1: Just checks if identity is registered
        // In Phase 2: Checks if identity has required claims (including accreditation)
        return _isVerified(to);
    }

    /*//////////////////////////////////////////////////////////////
                          STATE UPDATES
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice No state to update (stateless module)
     * @dev This module doesn't track any state
     * @dev Accreditation status is stored in identity contracts, not here
     */
    function moduleTransferAction(address from, address to, uint256 amount)
        external
        override
        onlyBoundCompliance
    {
        // No-op: Stateless module
    }

    /**
     * @notice No state to update on mint
     */
    function moduleMintAction(address to, uint256 amount) external override onlyBoundCompliance {
        // No-op: Stateless module
    }

    /**
     * @notice No state to update on burn
     */
    function moduleBurnAction(address from, uint256 amount) external override onlyBoundCompliance {
        // No-op: Stateless module
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get the module name
     * @return name The module identifier
     */
    function name() external pure override returns (string memory) {
        return "AccreditedInvestorModule";
    }

    /**
     * @notice Check if an address is accredited
     * @param investor The address to check
     * @return accredited True if the investor is verified (and accredited in Phase 2)
     * 
     * @dev Helper function for external queries
     * @dev Same logic as moduleCheck, but simpler interface
     */
    function isAccredited(address investor) external view returns (bool) {
        return _isVerified(investor);
    }
}
