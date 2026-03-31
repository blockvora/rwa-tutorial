// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

/**
 * @title IModularCompliance
 * @notice Interface for the modular compliance orchestrator
 * @dev Based on ERC-3643 standard, simplified for tutorial
 * 
 * The ModularCompliance contract orchestrates multiple compliance modules.
 * Each module implements a specific regulatory rule (max balance, accreditation, etc.)
 * 
 * Key concepts:
 * - Modules are pluggable (add/remove without redeploying token)
 * - All modules must pass for transfer to succeed
 * - Modules maintain their own state (balances, counters, etc.)
 * - Token contract calls compliance, compliance calls modules
 */
interface IModularCompliance {
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Emitted when the compliance is bound to a token
     * @param token The token contract address
     */
    event TokenBound(address indexed token);

    /**
     * @notice Emitted when the compliance is unbound from a token
     * @param token The token contract address
     */
    event TokenUnbound(address indexed token);

    /**
     * @notice Emitted when a module is added
     * @param module The module contract address
     */
    event ModuleAdded(address indexed module);

    /**
     * @notice Emitted when a module is removed
     * @param module The module contract address
     */
    event ModuleRemoved(address indexed module);

    /*//////////////////////////////////////////////////////////////
                            TOKEN BINDING
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Bind this compliance contract to a token
     * @param token The token contract address
     * 
     * @dev Only the token itself or the compliance owner can call this
     * @dev A compliance can only be bound to one token at a time
     */
    function bindToken(address token) external;

    /**
     * @notice Unbind this compliance contract from a token
     * @param token The token contract address
     * 
     * @dev Only the token itself or the compliance owner can call this
     */
    function unbindToken(address token) external;

    /*//////////////////////////////////////////////////////////////
                          MODULE MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Add a compliance module
     * @param module The module contract address
     * 
     * @dev Only callable by owner
     * @dev Module will be bound to this compliance
     * @dev Limited to MAX_MODULES (25) to prevent gas DoS
     */
    function addModule(address module) external;

    /**
     * @notice Remove a compliance module
     * @param module The module contract address
     * 
     * @dev Only callable by owner
     * @dev Module will be unbound from this compliance
     */
    function removeModule(address module) external;

    /*//////////////////////////////////////////////////////////////
                          COMPLIANCE CHECKS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Check if a transfer is compliant with all modules
     * @param from The sender address
     * @param to The receiver address
     * @param amount The transfer amount
     * @return compliant True if all modules allow the transfer
     * 
     * @dev This is a VIEW function (no state changes)
     * @dev Called by token contract before executing transfer
     * @dev Iterates through all modules and checks each one
     * @dev Returns false if ANY module rejects the transfer
     */
    function canTransfer(address from, address to, uint256 amount) external view returns (bool);

    /*//////////////////////////////////////////////////////////////
                          STATE UPDATES
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Notify modules that a transfer occurred
     * @param from The sender address
     * @param to The receiver address
     * @param amount The transfer amount
     * 
     * @dev Called by token contract AFTER transfer executes
     * @dev Allows modules to update their state (balances, counters, etc.)
     * @dev If any module reverts, the entire transaction reverts
     */
    function transferred(address from, address to, uint256 amount) external;

    /**
     * @notice Notify modules that tokens were minted
     * @param to The receiver address
     * @param amount The mint amount
     * 
     * @dev Called by token contract AFTER mint executes
     */
    function created(address to, uint256 amount) external;

    /**
     * @notice Notify modules that tokens were burned
     * @param from The sender address
     * @param amount The burn amount
     * 
     * @dev Called by token contract AFTER burn executes
     */
    function destroyed(address from, uint256 amount) external;

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get the token bound to this compliance
     * @return token The token contract address (address(0) if not bound)
     */
    function getTokenBound() external view returns (address);

    /**
     * @notice Get all active modules
     * @return modules Array of module addresses
     */
    function getModules() external view returns (address[] memory);

    /**
     * @notice Check if a module is bound to this compliance
     * @param module The module address to check
     * @return bound True if the module is active
     */
    function isModuleBound(address module) external view returns (bool);
}
