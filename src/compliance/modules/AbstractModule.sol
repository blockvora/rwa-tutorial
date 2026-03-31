// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IModule} from "../interfaces/IModule.sol";
import {IIdentityRegistry} from "../../identity/interfaces/IIdentityRegistry.sol";
import {IIdentity} from "../../identity/interfaces/IIdentity.sol";

/**
 * @title AbstractModule
 * @notice Base contract for all compliance modules
 * @dev Provides common functionality for module implementations
 * 
 * Features:
 * - Compliance binding management
 * - Identity registry integration
 * - Helper functions for common operations
 * - Access control for module functions
 * 
 * Inherit from this to create new modules:
 * 1. Override moduleCheck() with your compliance logic
 * 2. Override state update functions if you need to track state
 * 3. Implement name() to identify your module
 */
abstract contract AbstractModule is IModule, Ownable {
    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice Mapping of compliance contracts this module is bound to
    mapping(address => bool) private _boundCompliances;

    /// @notice Identity registry for looking up investor identities
    IIdentityRegistry internal _identityRegistry;

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Restrict function to only bound compliance contracts
     * @dev Used for state update functions (moduleTransferAction, etc.)
     */
    modifier onlyBoundCompliance() {
        require(_boundCompliances[msg.sender], "AbstractModule: caller is not a bound compliance");
        _;
    }

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initialize the module with an identity registry
     * @param identityRegistry The identity registry contract address
     * 
     * @dev Most modules need access to identity registry for checks
     */
    constructor(address identityRegistry) Ownable(msg.sender) {
        require(identityRegistry != address(0), "AbstractModule: invalid identity registry");
        _identityRegistry = IIdentityRegistry(identityRegistry);
    }

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
    function bindCompliance(address compliance) external override {
        require(compliance != address(0), "AbstractModule: invalid compliance address");
        require(!_boundCompliances[compliance], "AbstractModule: already bound");

        _boundCompliances[compliance] = true;

        emit ComplianceBound(compliance);
    }

    /**
     * @notice Unbind this module from a compliance contract
     * @param compliance The compliance contract address
     * 
     * @dev Only callable by the compliance contract itself
     * @dev Called automatically when compliance.removeModule() is executed
     */
    function unbindCompliance(address compliance) external override {
        require(compliance != address(0), "AbstractModule: invalid compliance address");
        require(_boundCompliances[compliance], "AbstractModule: not bound");

        _boundCompliances[compliance] = false;

        emit ComplianceUnbound(compliance);
    }

    /*//////////////////////////////////////////////////////////////
                          COMPLIANCE CHECKS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Check if a transfer complies with this module's rule
     * @dev MUST be overridden by inheriting contracts
     */
    function moduleCheck(address from, address to, uint256 amount, address compliance)
        external
        view
        virtual
        override
        returns (bool);

    /*//////////////////////////////////////////////////////////////
                          STATE UPDATES
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Update module state after a transfer
     * @dev Override if your module needs to track state
     * @dev Default implementation is no-op (for stateless modules)
     */
    function moduleTransferAction(address from, address to, uint256 amount)
        external
        virtual
        override
        onlyBoundCompliance
    {
        // Default: no state to update
        // Override in stateful modules (MaxBalance, TransferLimit, etc.)
    }

    /**
     * @notice Update module state after a mint
     * @dev Override if your module needs to track mints
     */
    function moduleMintAction(address to, uint256 amount) external virtual override onlyBoundCompliance {
        // Default: no state to update
    }

    /**
     * @notice Update module state after a burn
     * @dev Override if your module needs to track burns
     */
    function moduleBurnAction(address from, uint256 amount) external virtual override onlyBoundCompliance {
        // Default: no state to update
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Check if this module is bound to a compliance contract
     * @param compliance The compliance contract address
     * @return bound True if bound
     */
    function isComplianceBound(address compliance) external view override returns (bool) {
        return _boundCompliances[compliance];
    }

    /**
     * @notice Get the name of this module
     * @dev MUST be overridden by inheriting contracts
     */
    function name() external pure virtual override returns (string memory);

    /*//////////////////////////////////////////////////////////////
                          HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get the identity contract for a wallet address
     * @param wallet The wallet address
     * @return identity The identity contract (address(0) if not registered)
     * 
     * @dev Helper function for modules that need identity lookups
     */
    function _getIdentity(address wallet) internal view returns (address) {
        return address(_identityRegistry.identity(wallet));
    }

    /**
     * @notice Check if a wallet is verified in the identity registry
     * @param wallet The wallet address
     * @return verified True if verified
     * 
     * @dev Helper function for modules that need verification checks
     */
    function _isVerified(address wallet) internal view returns (bool) {
        return _identityRegistry.isVerified(wallet);
    }

    /**
     * @notice Get the country code for a wallet
     * @param wallet The wallet address
     * @return country The country code (0 if not registered)
     * 
     * @dev Helper function for country-based modules
     */
    function _getCountry(address wallet) internal view returns (uint16) {
        return _identityRegistry.investorCountry(wallet);
    }

    /*//////////////////////////////////////////////////////////////
                          ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Update the identity registry address
     * @param identityRegistry The new identity registry address
     * 
     * @dev Only callable by owner
     * @dev Useful if identity registry is upgraded
     */
    function setIdentityRegistry(address identityRegistry) external onlyOwner {
        require(identityRegistry != address(0), "AbstractModule: invalid identity registry");
        _identityRegistry = IIdentityRegistry(identityRegistry);
    }

    /**
     * @notice Get the identity registry address
     * @return identityRegistry The identity registry address
     */
    function getIdentityRegistry() external view returns (address) {
        return address(_identityRegistry);
    }
}
