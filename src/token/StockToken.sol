// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IStockToken} from "./interfaces/IStockToken.sol";
import {IIdentityRegistry} from "../identity/interfaces/IIdentityRegistry.sol";
import {IModularCompliance} from "../compliance/interfaces/IModularCompliance.sol";
import {IAttestationOracle} from "../oracle/interfaces/IAttestationOracle.sol";

/**
 * @title StockToken
 * @notice Permissioned stock token with identity verification and compliance enforcement
 * @dev Combines ERC-3643 (identity + compliance) with RWA lifecycle (redemption)
 * 
 * ARCHITECTURE:
 * 
 * StockToken
 * ├─ ERC20 (balances, transfers)
 * ├─ AccessControl (owner, agents)
 * ├─ IdentityRegistry (who can hold tokens?)
 * ├─ ModularCompliance (what rules apply?)
 * └─ Freezing (regulatory controls)
 * 
 * TRANSFER FLOW:
 * 1. Check token not paused
 * 2. Check sender/receiver not frozen
 * 3. Check sender has unfrozen balance
 * 4. Check receiver is verified (IdentityRegistry)
 * 5. Check compliance rules (ModularCompliance)
 * 6. Execute transfer
 * 7. Notify compliance of transfer
 * 
 * SECURITY MODEL:
 * - Owner: Can set identity registry, compliance, manage agents
 * - Agents: Can mint, burn, freeze, forced transfer
 * - Investors: Can transfer (if verified and compliant)
 */
contract StockToken is IStockToken, ERC20, AccessControl {
    /*//////////////////////////////////////////////////////////////
                                 ROLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Role for agents who can manage tokens
    bytes32 public constant AGENT_ROLE = keccak256("AGENT_ROLE");

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice Identity registry for investor verification
    IIdentityRegistry private _identityRegistry;

    /// @notice Compliance contract for transfer rules
    IModularCompliance private _compliance;

    /// @notice Redemption manager for async redemptions (optional)
    address private _redemptionManager;

    /// @notice Attestation oracle for reserve verification (optional)
    IAttestationOracle private _attestationOracle;

    /// @notice Require oracle attestation before minting (default: false for tutorial)
    bool private _requireAttestation;

    /// @notice Token pause state
    bool private _paused;

    /// @notice Mapping of frozen addresses (cannot send or receive)
    mapping(address => bool) private _frozen;

    /// @notice Mapping of partially frozen tokens (cannot be transferred)
    mapping(address => uint256) private _frozenTokens;

    /// @notice Token decimals
    uint8 private immutable _decimals;

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Restrict function to agents only
     */
    modifier onlyAgent() {
        require(hasRole(AGENT_ROLE, msg.sender), "StockToken: caller is not an agent");
        _;
    }

    /**
     * @notice Restrict function to when token is not paused
     */
    modifier whenNotPaused() {
        require(!_paused, "StockToken: token is paused");
        _;
    }

    /**
     * @notice Restrict function to when token is paused
     */
    modifier whenPaused() {
        require(_paused, "StockToken: token is not paused");
        _;
    }

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initialize the stock token
     * @param name_ Token name
     * @param symbol_ Token symbol
     * @param decimals_ Token decimals
     * @param identityRegistry_ Identity registry address
     * @param compliance_ Compliance contract address
     * 
     * @dev Deployer becomes admin and first agent
     * @dev Token starts paused (must be unpaused by agent)
     */
    constructor(
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        address identityRegistry_,
        address compliance_
    ) ERC20(name_, symbol_) {
        require(identityRegistry_ != address(0), "StockToken: invalid identity registry");
        require(compliance_ != address(0), "StockToken: invalid compliance");
        require(decimals_ <= 18, "StockToken: decimals must be <= 18");

        _decimals = decimals_;
        _identityRegistry = IIdentityRegistry(identityRegistry_);
        _compliance = IModularCompliance(compliance_);
        _paused = true; // Start paused for safety

        // Grant roles to deployer
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(AGENT_ROLE, msg.sender);

        // Bind compliance to this token
        _compliance.bindToken(address(this));

        emit IdentityRegistrySet(identityRegistry_);
        emit ComplianceSet(compliance_);
    }

    /*//////////////////////////////////////////////////////////////
                          TRANSFER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Transfer tokens with identity and compliance checks
     * @param to The receiver address
     * @param amount The amount to transfer
     * @return success True if transfer succeeded
     */
    function transfer(address to, uint256 amount) public override(ERC20, IStockToken) whenNotPaused returns (bool) {
        address from = msg.sender;

        // Check freezing
        require(!_frozen[from] && !_frozen[to], "StockToken: address is frozen");

        // Check unfrozen balance
        require(balanceOf(from) - _frozenTokens[from] >= amount, "StockToken: insufficient unfrozen balance");

        // Check identity verification
        require(_identityRegistry.isVerified(to), "StockToken: receiver not verified");

        // Check compliance
        require(_compliance.canTransfer(from, to, amount), "StockToken: transfer not compliant");

        // Execute transfer
        _transfer(from, to, amount);

        // Notify compliance
        _compliance.transferred(from, to, amount);

        return true;
    }

    /**
     * @notice Transfer tokens from another address
     * @param from The sender address
     * @param to The receiver address
     * @param amount The amount to transfer
     * @return success True if transfer succeeded
     */
    function transferFrom(address from, address to, uint256 amount)
        public
        override(ERC20, IStockToken)
        whenNotPaused
        returns (bool)
    {
        // Check freezing
        require(!_frozen[from] && !_frozen[to], "StockToken: address is frozen");

        // Check unfrozen balance
        require(balanceOf(from) - _frozenTokens[from] >= amount, "StockToken: insufficient unfrozen balance");

        // Check identity verification
        require(_identityRegistry.isVerified(to), "StockToken: receiver not verified");

        // Check compliance
        require(_compliance.canTransfer(from, to, amount), "StockToken: transfer not compliant");

        // Update allowance and execute transfer
        _spendAllowance(from, msg.sender, amount);
        _transfer(from, to, amount);

        // Notify compliance
        _compliance.transferred(from, to, amount);

        return true;
    }

    /**
     * @notice Batch transfer to multiple addresses
     * @param toList Array of receiver addresses
     * @param amounts Array of amounts to transfer
     */
    function batchTransfer(address[] calldata toList, uint256[] calldata amounts) external override {
        require(toList.length == amounts.length, "StockToken: arrays length mismatch");

        for (uint256 i = 0; i < toList.length; i++) {
            transfer(toList[i], amounts[i]);
        }
    }

    /*//////////////////////////////////////////////////////////////
                          MINT/BURN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Mint tokens to a verified investor
     * @param to The receiver address
     * @param amount The amount to mint
     */
    function mint(address to, uint256 amount) public override onlyAgent {
        _mintTo(to, amount);
    }

    /**
     * @dev Internal mint function
     * 
     * IMPORTANT: This is where backing verification should happen in production.
     * 
     * Production Requirements:
     * 1. Verify oracle attestation (stocks are held in custody)
     * 2. Check collateral ratio (e.g., 110% backing)
     * 3. Verify reserve value >= token value
     * 4. Rate limiting (daily mint caps)
     * 5. Multi-sig approval for large mints
     * 
     * Tutorial Implementation:
     * - Optional attestation oracle check (disabled by default)
     * - Demonstrates integration pattern
     * - Trusts agent to verify backing off-chain
     * 
     * Why Optional?
     * - Requires Chainlink Functions setup
     * - Requires real custody integration
     * - Adds deployment complexity
     * - Core pattern is demonstrated without it
     */
    function _mintTo(address to, uint256 amount) internal {
        require(to != address(0), "StockToken: mint to zero address");
        require(_identityRegistry.isVerified(to), "StockToken: receiver not verified");
        require(_compliance.canTransfer(address(0), to, amount), "StockToken: mint not compliant");

        // Optional: Verify backing via attestation oracle
        if (_requireAttestation && address(_attestationOracle) != address(0)) {
            require(
                _attestationOracle.hasReserves("STOCK", amount),
                "StockToken: insufficient reserves"
            );
        }

        _mint(to, amount);

        // Notify compliance
        _compliance.created(to, amount);
    }

    /**
     * @notice Burn tokens from an address
     * @param from The address to burn from
     * @param amount The amount to burn
     */
    function burn(address from, uint256 amount) public override onlyAgent {
        _burnFrom(from, amount);
    }

    /**
     * @dev Internal burn function
     */
    function _burnFrom(address from, uint256 amount) internal {
        require(from != address(0), "StockToken: burn from zero address");
        require(balanceOf(from) >= amount, "StockToken: burn amount exceeds balance");

        // Unfreeze tokens if needed
        uint256 freeBalance = balanceOf(from) - _frozenTokens[from];
        if (amount > freeBalance) {
            uint256 tokensToUnfreeze = amount - freeBalance;
            _frozenTokens[from] -= tokensToUnfreeze;
            emit TokensUnfrozen(from, tokensToUnfreeze);
        }

        _burn(from, amount);

        // Notify compliance
        _compliance.destroyed(from, amount);
    }

    /**
     * @notice Batch mint to multiple addresses
     * @param toList Array of receiver addresses
     * @param amounts Array of amounts to mint
     */
    function batchMint(address[] calldata toList, uint256[] calldata amounts) external override onlyAgent {
        require(toList.length == amounts.length, "StockToken: arrays length mismatch");

        for (uint256 i = 0; i < toList.length; i++) {
            _mintTo(toList[i], amounts[i]);
        }
    }

    /**
     * @notice Batch burn from multiple addresses
     * @param fromList Array of addresses to burn from
     * @param amounts Array of amounts to burn
     */
    function batchBurn(address[] calldata fromList, uint256[] calldata amounts) external override onlyAgent {
        require(fromList.length == amounts.length, "StockToken: arrays length mismatch");

        for (uint256 i = 0; i < fromList.length; i++) {
            _burnFrom(fromList[i], amounts[i]);
        }
    }

    /*//////////////////////////////////////////////////////////////
                        FREEZING FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Freeze or unfreeze an entire wallet
     * @param wallet The wallet address
     * @param freeze True to freeze, false to unfreeze
     */
    function setAddressFrozen(address wallet, bool freeze) public override onlyAgent {
        _frozen[wallet] = freeze;
        emit AddressFrozen(wallet, freeze, msg.sender);
    }

    /**
     * @notice Freeze a partial amount of tokens in a wallet
     * @param wallet The wallet address
     * @param amount The amount to freeze
     */
    function freezePartialTokens(address wallet, uint256 amount) external override onlyAgent {
        require(
            balanceOf(wallet) >= _frozenTokens[wallet] + amount,
            "StockToken: amount exceeds available balance"
        );

        _frozenTokens[wallet] += amount;
        emit TokensFrozen(wallet, amount);
    }

    /**
     * @notice Unfreeze a partial amount of tokens
     * @param wallet The wallet address
     * @param amount The amount to unfreeze
     */
    function unfreezePartialTokens(address wallet, uint256 amount) external override onlyAgent {
        require(_frozenTokens[wallet] >= amount, "StockToken: amount exceeds frozen tokens");

        _frozenTokens[wallet] -= amount;
        emit TokensUnfrozen(wallet, amount);
    }

    /**
     * @notice Batch freeze/unfreeze multiple addresses
     * @param wallets Array of wallet addresses
     * @param freeze Array of freeze states
     */
    function batchSetAddressFrozen(address[] calldata wallets, bool[] calldata freeze) external override onlyAgent {
        require(wallets.length == freeze.length, "StockToken: arrays length mismatch");

        for (uint256 i = 0; i < wallets.length; i++) {
            setAddressFrozen(wallets[i], freeze[i]);
        }
    }

    /*//////////////////////////////////////////////////////////////
                        FORCED TRANSFER
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Force transfer tokens (regulatory action)
     * @param from The sender address
     * @param to The receiver address
     * @param amount The amount to transfer
     * @return success True if transfer succeeded
     */
    function forcedTransfer(address from, address to, uint256 amount) public override onlyAgent returns (bool) {
        return _forcedTransfer(from, to, amount);
    }

    /**
     * @dev Internal forced transfer function
     */
    function _forcedTransfer(address from, address to, uint256 amount) internal returns (bool) {
        require(balanceOf(from) >= amount, "StockToken: insufficient balance");

        // Unfreeze tokens if needed
        uint256 freeBalance = balanceOf(from) - _frozenTokens[from];
        if (amount > freeBalance) {
            uint256 tokensToUnfreeze = amount - freeBalance;
            _frozenTokens[from] -= tokensToUnfreeze;
            emit TokensUnfrozen(from, tokensToUnfreeze);
        }

        // Check receiver is verified
        require(_identityRegistry.isVerified(to), "StockToken: receiver not verified");

        // Execute transfer (bypass compliance for forced transfers)
        _transfer(from, to, amount);

        // Notify compliance
        _compliance.transferred(from, to, amount);

        return true;
    }

    /**
     * @notice Batch forced transfers
     * @param fromList Array of sender addresses
     * @param toList Array of receiver addresses
     * @param amounts Array of amounts
     */
    function batchForcedTransfer(
        address[] calldata fromList,
        address[] calldata toList,
        uint256[] calldata amounts
    ) external override onlyAgent {
        require(
            fromList.length == toList.length && toList.length == amounts.length,
            "StockToken: arrays length mismatch"
        );

        for (uint256 i = 0; i < fromList.length; i++) {
            _forcedTransfer(fromList[i], toList[i], amounts[i]);
        }
    }

    /*//////////////////////////////////////////////////////////////
                        REDEMPTION FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Request redemption of tokens for underlying asset
     * @param amount The amount of tokens to redeem
     * 
     * @dev If RedemptionManager is set, delegates to it (recommended)
     * @dev Otherwise, burns tokens and emits event for manual processing
     * 
     * IMPORTANT: In production, you MUST use a RedemptionManager to:
     * - Track redemption requests
     * - Handle async settlement
     * - Manage USDC payouts
     * - Prevent loss of funds
     */
    function requestRedemption(uint256 amount) external override whenNotPaused {
        require(amount > 0, "StockToken: amount must be positive");
        require(balanceOf(msg.sender) >= amount, "StockToken: insufficient balance");
        require(!_frozen[msg.sender], "StockToken: address is frozen");

        if (_redemptionManager != address(0)) {
            // Integrated mode: RedemptionManager handles everything
            // User will call RedemptionManager.requestRedemption() directly
            // This function is kept for backwards compatibility
            revert("StockToken: use RedemptionManager.requestRedemption()");
        } else {
            // Fallback mode: Manual processing (NOT RECOMMENDED for production)
            // Tokens are burned immediately with no redemption tracking
            // Oracle must monitor events and process manually
            
            _burn(msg.sender, amount);
            _compliance.destroyed(msg.sender, amount);
            
            emit RedemptionRequested(msg.sender, amount);
        }
    }

    /*//////////////////////////////////////////////////////////////
                        PAUSE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Pause all token transfers
     */
    function pause() external override onlyAgent whenNotPaused {
        _paused = true;
        emit Paused(msg.sender);
    }

    /**
     * @notice Unpause token transfers
     */
    function unpause() external override onlyAgent whenPaused {
        _paused = false;
        emit Unpaused(msg.sender);
    }

    /*//////////////////////////////////////////////////////////////
                        ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Set the identity registry
     * @param identityRegistry_ The identity registry address
     */
    function setIdentityRegistry(address identityRegistry_) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        require(identityRegistry_ != address(0), "StockToken: invalid identity registry");
        _identityRegistry = IIdentityRegistry(identityRegistry_);
        emit IdentityRegistrySet(identityRegistry_);
    }

    /**
     * @notice Set the compliance contract
     * @param compliance_ The compliance contract address
     */
    function setCompliance(address compliance_) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        require(compliance_ != address(0), "StockToken: invalid compliance");

        // Unbind old compliance
        if (address(_compliance) != address(0)) {
            _compliance.unbindToken(address(this));
        }

        // Set and bind new compliance
        _compliance = IModularCompliance(compliance_);
        _compliance.bindToken(address(this));

        emit ComplianceSet(compliance_);
    }

    /**
     * @notice Set the redemption manager (optional)
     * @param redemptionManager_ The redemption manager address
     * 
     * @dev Set to address(0) to disable integration (fallback to manual mode)
     * @dev When set, requestRedemption() will revert and direct users to RedemptionManager
     */
    function setRedemptionManager(address redemptionManager_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _redemptionManager = redemptionManager_;
        emit RedemptionManagerSet(redemptionManager_);
    }

    /**
     * @notice Set the attestation oracle (optional)
     * @param attestationOracle_ The attestation oracle address
     * 
     * @dev Set to address(0) to disable attestation checks
     * @dev When enabled, minting will verify reserves via oracle
     */
    function setAttestationOracle(address attestationOracle_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _attestationOracle = IAttestationOracle(attestationOracle_);
        emit AttestationOracleSet(attestationOracle_);
    }

    /**
     * @notice Enable or disable attestation requirement
     * @param required Whether to require attestation for minting
     * 
     * @dev Default: false (tutorial mode, trusts agent)
     * @dev Production: true (requires oracle verification)
     */
    function setRequireAttestation(bool required) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _requireAttestation = required;
        emit AttestationRequirementSet(required);
    }

    /*//////////////////////////////////////////////////////////////
                          VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get the identity registry address
     * @return identityRegistry The identity registry
     */
    function identityRegistry() external view override returns (IIdentityRegistry) {
        return _identityRegistry;
    }

    /**
     * @notice Get the compliance contract address
     * @return compliance The compliance contract
     */
    function compliance() external view override returns (IModularCompliance) {
        return _compliance;
    }

    /**
     * @notice Check if token is paused
     * @return isPaused True if paused
     */
    function paused() external view override returns (bool) {
        return _paused;
    }

    /**
     * @notice Check if an address is frozen
     * @param wallet The wallet address
     * @return frozen True if frozen
     */
    function isFrozen(address wallet) external view override returns (bool) {
        return _frozen[wallet];
    }

    /**
     * @notice Get the amount of frozen tokens for an address
     * @param wallet The wallet address
     * @return frozenAmount The amount of frozen tokens
     */
    function getFrozenTokens(address wallet) external view override returns (uint256) {
        return _frozenTokens[wallet];
    }

    /**
     * @notice Get token decimals
     * @return tokenDecimals The token decimals
     */
    function decimals() public view override(ERC20, IStockToken) returns (uint8) {
        return _decimals;
    }

    /**
     * @notice Get the redemption manager address
     * @return redemptionManager The redemption manager (address(0) if not set)
     */
    function redemptionManager() external view returns (address) {
        return _redemptionManager;
    }

    /**
     * @notice Get the attestation oracle address
     * @return attestationOracle The attestation oracle (address(0) if not set)
     */
    function attestationOracle() external view returns (IAttestationOracle) {
        return _attestationOracle;
    }

    /**
     * @notice Check if attestation is required for minting
     * @return required True if attestation is required
     */
    function requiresAttestation() external view returns (bool) {
        return _requireAttestation;
    }
}
