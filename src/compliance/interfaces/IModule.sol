// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

/**
 * @title IModule
 * @notice Interface for compliance modules
 * @dev Based on ERC-3643 standard
 * 
 * A compliance module implements a specific regulatory rule:
 * - AccreditedInvestorModule: Only accredited investors can receive tokens
 * - MaxBalanceModule: Limit tokens per identity
 * - TransferLimitModule: Limit transfers per time period
 * - CountryRestrictionModule: Block certain jurisdictions
 * 
 * Module lifecycle:
 * 1. Deploy module
 * 2. Compliance.addModule(module) → calls module.bindCompliance()
 * 3. Module is now active
 * 4. Every transfer calls module.moduleCheck()
 * 5. After transfer, module.moduleTransferAction() updates state
 * 6. Compliance.removeModule(module) → calls module.unbindCompliance()
 */
interface IModule {
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Emitted when the module is bound to a compliance contract
     * @param compliance The compliance contract address
     */
    event ComplianceBound(address indexed compliance);

    /**
     * @notice Emitted when the module is unbound from a compliance contract
     * @param compliance The compliance contract address
     */
    event ComplianceUnbound(address indexed compliance);

    /*//////////////////////////////////////////////////////////////
                          BINDING FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Bind this module to a compliance contract
     * @param compliance The compliance contract address
     * 
     * @dev Only callable by the compliance contract itself
     * @dev Called automatically when compliance.addModule() is executed
     */
    function bindCompliance(address compliance) external;

    /**
     * @notice Unbind this module from a compliance contract
     * @param compliance The compliance contract address
     * 
     * @dev Only callable by the compliance contract itself
     * @dev Called automatically when compliance.removeModule() is executed
     */
    function unbindCompliance(address compliance) external;

    /*//////////////////////////////////////////////////////////////
                          COMPLIANCE CHECKS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Check if a transfer complies with this module's rule
     * @param from The sender address
     * @param to The receiver address
     * @param amount The transfer amount
     * @param compliance The compliance contract calling this check
     * @return compliant True if the transfer is allowed by this module
     * 
     * @dev This is a VIEW function (no state changes)
     * @dev Called by ModularCompliance.canTransfer()
     * @dev Should be gas-efficient (called on every transfer)
     * 
     * Examples:
     * - AccreditedInvestorModule: Check if 'to' has accreditation claim
     * - MaxBalanceModule: Check if 'to' balance + amount <= max
     * - TransferLimitModule: Check if daily volume + amount <= limit
     */
    function moduleCheck(address from, address to, uint256 amount, address compliance)
        external
        view
        returns (bool);

    /*//////////////////////////////////////////////////////////////
                          STATE UPDATES
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Update module state after a transfer
     * @param from The sender address
     * @param to The receiver address
     * @param amount The transfer amount
     * 
     * @dev Called by ModularCompliance.transferred() AFTER transfer executes
     * @dev Use this to update counters, balances, or other state
     * @dev If this reverts, the entire transaction reverts
     * 
     * Examples:
     * - MaxBalanceModule: Update identity balances
     * - TransferLimitModule: Increment daily transfer counter
     * - CountryRestrictionModule: No state to update (no-op)
     */
    function moduleTransferAction(address from, address to, uint256 amount) external;

    /**
     * @notice Update module state after a mint
     * @param to The receiver address
     * @param amount The mint amount
     * 
     * @dev Called by ModularCompliance.created() AFTER mint executes
     */
    function moduleMintAction(address to, uint256 amount) external;

    /**
     * @notice Update module state after a burn
     * @param from The sender address
     * @param amount The burn amount
     * 
     * @dev Called by ModularCompliance.destroyed() AFTER burn executes
     */
    function moduleBurnAction(address from, uint256 amount) external;

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Check if this module is bound to a compliance contract
     * @param compliance The compliance contract address
     * @return bound True if bound to this compliance
     */
    function isComplianceBound(address compliance) external view returns (bool);

    /**
     * @notice Get the name of this module
     * @return name The module name (e.g., "AccreditedInvestorModule")
     * 
     * @dev Used for identification and debugging
     */
    function name() external pure returns (string memory);
}
