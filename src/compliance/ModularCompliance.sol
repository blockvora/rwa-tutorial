// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IModularCompliance} from "./interfaces/IModularCompliance.sol";
import {IModule} from "./interfaces/IModule.sol";

/**
 * @title ModularCompliance
 * @notice Orchestrates multiple compliance modules for regulatory enforcement
 * @dev Simplified ERC-3643 implementation for tutorial
 * 
 * ARCHITECTURE:
 * 
 * Token → ModularCompliance → [Module1, Module2, Module3, ...]
 * 
 * Flow:
 * 1. Token calls canTransfer(from, to, amount)
 * 2. Compliance iterates through all modules
 * 3. Each module.moduleCheck() must return true
 * 4. If all pass, return true to token
 * 5. Token executes transfer
 * 6. Token calls transferred(from, to, amount)
 * 7. Compliance notifies all modules to update state
 * 
 * SECURITY:
 * - Only bound token can call transferred/created/destroyed
 * - Only owner can add/remove modules
 * - Limited to MAX_MODULES to prevent gas DoS
 * - Modules are called in order (deterministic)
 */
contract ModularCompliance is IModularCompliance, Ownable {
    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice The token contract bound to this compliance
    address private _tokenBound;

    /// @notice Array of active module addresses
    address[] private _modules;

    /// @notice Mapping to check if a module is bound (for O(1) lookup)
    mapping(address => bool) private _moduleBound;

    /// @notice Maximum number of modules (prevent gas DoS)
    uint256 public constant MAX_MODULES = 25;

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Restrict function to only the bound token
     * @dev Used for state update functions (transferred, created, destroyed)
     */
    modifier onlyToken() {
        require(msg.sender == _tokenBound, "ModularCompliance: caller is not the bound token");
        _;
    }

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor() Ownable(msg.sender) {}

    /*//////////////////////////////////////////////////////////////
                            TOKEN BINDING
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Bind this compliance to a token
     * @param token The token contract address
     * 
     * @dev Can be called by owner or by the token itself (during token.setCompliance())
     * @dev A compliance can only be bound to one token at a time
     */
    function bindToken(address token) external override {
        require(
            msg.sender == owner() || (_tokenBound == address(0) && msg.sender == token),
            "ModularCompliance: only owner or token can bind"
        );
        require(token != address(0), "ModularCompliance: invalid token address");

        _tokenBound = token;

        emit TokenBound(token);
    }

    /**
     * @notice Unbind this compliance from a token
     * @param token The token contract address
     * 
     * @dev Can be called by owner or by the token itself
     */
    function unbindToken(address token) external override {
        require(msg.sender == owner() || msg.sender == token, "ModularCompliance: only owner or token can unbind");
        require(token == _tokenBound, "ModularCompliance: token is not bound");
        require(token != address(0), "ModularCompliance: invalid token address");

        delete _tokenBound;

        emit TokenUnbound(token);
    }

    /*//////////////////////////////////////////////////////////////
                          MODULE MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Add a compliance module
     * @param module The module contract address
     * 
     * @dev Only callable by owner
     * @dev Binds the module to this compliance
     * @dev Limited to MAX_MODULES to prevent gas exhaustion
     */
    function addModule(address module) external override onlyOwner {
        require(module != address(0), "ModularCompliance: invalid module address");
        require(!_moduleBound[module], "ModularCompliance: module already bound");
        require(_modules.length < MAX_MODULES, "ModularCompliance: too many modules");

        // Bind the module to this compliance
        IModule(module).bindCompliance(address(this));

        // Add to array and mapping
        _modules.push(module);
        _moduleBound[module] = true;

        emit ModuleAdded(module);
    }

    /**
     * @notice Remove a compliance module
     * @param module The module contract address
     * 
     * @dev Only callable by owner
     * @dev Unbinds the module from this compliance
     * @dev Removes from array by swapping with last element
     */
    function removeModule(address module) external override onlyOwner {
        require(module != address(0), "ModularCompliance: invalid module address");
        require(_moduleBound[module], "ModularCompliance: module not bound");

        // Unbind the module
        IModule(module).unbindCompliance(address(this));

        // Find and remove from array
        uint256 length = _modules.length;
        for (uint256 i = 0; i < length; i++) {
            if (_modules[i] == module) {
                // Swap with last element and pop
                _modules[i] = _modules[length - 1];
                _modules.pop();
                break;
            }
        }

        // Remove from mapping
        _moduleBound[module] = false;

        emit ModuleRemoved(module);
    }

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
     * @dev VIEW function (no state changes)
     * @dev Iterates through all modules
     * @dev Returns false if ANY module rejects
     * @dev Gas cost: O(n) where n = number of modules
     */
    function canTransfer(address from, address to, uint256 amount) external view override returns (bool) {
        uint256 length = _modules.length;

        // If no modules, transfer is allowed (default permissive)
        if (length == 0) {
            return true;
        }

        // Check each module
        for (uint256 i = 0; i < length; i++) {
            if (!IModule(_modules[i]).moduleCheck(from, to, amount, address(this))) {
                return false; // Module rejected, transfer not compliant
            }
        }

        return true; // All modules passed
    }

    /*//////////////////////////////////////////////////////////////
                          STATE UPDATES
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Notify modules that a transfer occurred
     * @param from The sender address
     * @param to The receiver address
     * @param amount The transfer amount
     * 
     * @dev Only callable by bound token
     * @dev Called AFTER transfer executes
     * @dev Allows modules to update state (balances, counters, etc.)
     * @dev If any module reverts, entire transaction reverts
     */
    function transferred(address from, address to, uint256 amount) external override onlyToken {
        require(from != address(0) && to != address(0), "ModularCompliance: invalid addresses");
        require(amount > 0, "ModularCompliance: invalid amount");

        uint256 length = _modules.length;
        for (uint256 i = 0; i < length; i++) {
            IModule(_modules[i]).moduleTransferAction(from, to, amount);
        }
    }

    /**
     * @notice Notify modules that tokens were minted
     * @param to The receiver address
     * @param amount The mint amount
     * 
     * @dev Only callable by bound token
     * @dev Called AFTER mint executes
     */
    function created(address to, uint256 amount) external override onlyToken {
        require(to != address(0), "ModularCompliance: invalid address");
        require(amount > 0, "ModularCompliance: invalid amount");

        uint256 length = _modules.length;
        for (uint256 i = 0; i < length; i++) {
            IModule(_modules[i]).moduleMintAction(to, amount);
        }
    }

    /**
     * @notice Notify modules that tokens were burned
     * @param from The sender address
     * @param amount The burn amount
     * 
     * @dev Only callable by bound token
     * @dev Called AFTER burn executes
     */
    function destroyed(address from, uint256 amount) external override onlyToken {
        require(from != address(0), "ModularCompliance: invalid address");
        require(amount > 0, "ModularCompliance: invalid amount");

        uint256 length = _modules.length;
        for (uint256 i = 0; i < length; i++) {
            IModule(_modules[i]).moduleBurnAction(from, amount);
        }
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get the token bound to this compliance
     * @return token The token contract address
     */
    function getTokenBound() external view override returns (address) {
        return _tokenBound;
    }

    /**
     * @notice Get all active modules
     * @return modules Array of module addresses
     */
    function getModules() external view override returns (address[] memory) {
        return _modules;
    }

    /**
     * @notice Check if a module is bound
     * @param module The module address
     * @return bound True if the module is active
     */
    function isModuleBound(address module) external view override returns (bool) {
        return _moduleBound[module];
    }
}
