// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IIdentityRegistry} from "../../identity/interfaces/IIdentityRegistry.sol";
import {IModularCompliance} from "../../compliance/interfaces/IModularCompliance.sol";

/**
 * @title IStockToken
 * @notice Interface for permissioned stock tokens
 * @dev Combines ERC-3643 (identity + compliance) with RWA lifecycle (redemption)
 * 
 * Key features:
 * - ERC20 base with identity verification
 * - Compliance checks on all transfers
 * - Agent-controlled minting/burning
 * - Wallet freezing for regulatory actions
 * - Redemption requests for stock liquidation
 * 
 * Based on:
 * - ERC-3643 Token standard
 * - rwa-creator dTSLA lifecycle
 */
interface IStockToken is IERC20 {
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Emitted when identity registry is updated
     * @param identityRegistry The new identity registry address
     */
    event IdentityRegistrySet(address indexed identityRegistry);

    /**
     * @notice Emitted when compliance contract is updated
     * @param compliance The new compliance contract address
     */
    event ComplianceSet(address indexed compliance);

    /**
     * @notice Emitted when token is paused
     * @param agent The agent who paused the token
     */
    event Paused(address indexed agent);

    /**
     * @notice Emitted when token is unpaused
     * @param agent The agent who unpaused the token
     */
    event Unpaused(address indexed agent);

    /**
     * @notice Emitted when an address is frozen
     * @param wallet The frozen wallet address
     * @param frozen True if frozen, false if unfrozen
     * @param agent The agent who performed the action
     */
    event AddressFrozen(address indexed wallet, bool frozen, address indexed agent);

    /**
     * @notice Emitted when tokens are partially frozen
     * @param wallet The wallet address
     * @param amount The amount of tokens frozen
     */
    event TokensFrozen(address indexed wallet, uint256 amount);

    /**
     * @notice Emitted when tokens are partially unfrozen
     * @param wallet The wallet address
     * @param amount The amount of tokens unfrozen
     */
    event TokensUnfrozen(address indexed wallet, uint256 amount);

    /**
     * @notice Emitted when a redemption is requested
     * @param investor The investor requesting redemption
     * @param amount The amount of tokens to redeem
     */
    event RedemptionRequested(address indexed investor, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                          TRANSFER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Transfer tokens with identity and compliance checks
     * @param to The receiver address
     * @param amount The amount to transfer
     * @return success True if transfer succeeded
     * 
     * @dev Checks:
     *      1. Token not paused
     *      2. Sender and receiver not frozen
     *      3. Sender has sufficient unfrozen balance
     *      4. Receiver is verified in identity registry
     *      5. Transfer passes compliance checks
     */
    function transfer(address to, uint256 amount) external override returns (bool);

    /**
     * @notice Transfer tokens from another address
     * @param from The sender address
     * @param to The receiver address
     * @param amount The amount to transfer
     * @return success True if transfer succeeded
     */
    function transferFrom(address from, address to, uint256 amount) external override returns (bool);

    /**
     * @notice Batch transfer to multiple addresses
     * @param toList Array of receiver addresses
     * @param amounts Array of amounts to transfer
     * 
     * @dev Only callable when not paused
     */
    function batchTransfer(address[] calldata toList, uint256[] calldata amounts) external;

    /*//////////////////////////////////////////////////////////////
                          MINT/BURN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Mint tokens to a verified investor
     * @param to The receiver address
     * @param amount The amount to mint
     * 
     * @dev Only callable by agents
     * @dev Receiver must be verified in identity registry
     * @dev Must pass compliance checks
     */
    function mint(address to, uint256 amount) external;

    /**
     * @notice Burn tokens from an address
     * @param from The address to burn from
     * @param amount The amount to burn
     * 
     * @dev Only callable by agents
     * @dev Can burn frozen tokens if needed
     */
    function burn(address from, uint256 amount) external;

    /**
     * @notice Batch mint to multiple addresses
     * @param toList Array of receiver addresses
     * @param amounts Array of amounts to mint
     */
    function batchMint(address[] calldata toList, uint256[] calldata amounts) external;

    /**
     * @notice Batch burn from multiple addresses
     * @param fromList Array of addresses to burn from
     * @param amounts Array of amounts to burn
     */
    function batchBurn(address[] calldata fromList, uint256[] calldata amounts) external;

    /*//////////////////////////////////////////////////////////////
                        FREEZING FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Freeze or unfreeze an entire wallet
     * @param wallet The wallet address
     * @param freeze True to freeze, false to unfreeze
     * 
     * @dev Only callable by agents
     * @dev Frozen wallets cannot send or receive tokens
     */
    function setAddressFrozen(address wallet, bool freeze) external;

    /**
     * @notice Freeze a partial amount of tokens in a wallet
     * @param wallet The wallet address
     * @param amount The amount to freeze
     * 
     * @dev Only callable by agents
     * @dev Frozen tokens cannot be transferred
     */
    function freezePartialTokens(address wallet, uint256 amount) external;

    /**
     * @notice Unfreeze a partial amount of tokens
     * @param wallet The wallet address
     * @param amount The amount to unfreeze
     * 
     * @dev Only callable by agents
     */
    function unfreezePartialTokens(address wallet, uint256 amount) external;

    /**
     * @notice Batch freeze/unfreeze multiple addresses
     * @param wallets Array of wallet addresses
     * @param freeze Array of freeze states
     */
    function batchSetAddressFrozen(address[] calldata wallets, bool[] calldata freeze) external;

    /*//////////////////////////////////////////////////////////////
                        FORCED TRANSFER
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Force transfer tokens (regulatory action)
     * @param from The sender address
     * @param to The receiver address
     * @param amount The amount to transfer
     * @return success True if transfer succeeded
     * 
     * @dev Only callable by agents
     * @dev Can transfer frozen tokens
     * @dev Used for court orders, wallet recovery, etc.
     */
    function forcedTransfer(address from, address to, uint256 amount) external returns (bool);

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
    ) external;

    /*//////////////////////////////////////////////////////////////
                        REDEMPTION FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Request redemption of tokens for underlying asset
     * @param amount The amount of tokens to redeem
     * 
     * @dev Burns tokens and emits event for off-chain processing
     * @dev Actual settlement happens via RedemptionManager (Phase 5)
     */
    function requestRedemption(uint256 amount) external;

    /*//////////////////////////////////////////////////////////////
                        PAUSE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Pause all token transfers
     * @dev Only callable by agents
     */
    function pause() external;

    /**
     * @notice Unpause token transfers
     * @dev Only callable by agents
     */
    function unpause() external;

    /*//////////////////////////////////////////////////////////////
                        ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Set the identity registry
     * @param identityRegistry The identity registry address
     * 
     * @dev Only callable by owner
     */
    function setIdentityRegistry(address identityRegistry) external;

    /**
     * @notice Set the compliance contract
     * @param compliance The compliance contract address
     * 
     * @dev Only callable by owner
     * @dev Binds compliance to this token
     */
    function setCompliance(address compliance) external;

    /*//////////////////////////////////////////////////////////////
                          VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get the identity registry address
     * @return identityRegistry The identity registry
     */
    function identityRegistry() external view returns (IIdentityRegistry);

    /**
     * @notice Get the compliance contract address
     * @return compliance The compliance contract
     */
    function compliance() external view returns (IModularCompliance);

    /**
     * @notice Check if token is paused
     * @return paused True if paused
     */
    function paused() external view returns (bool);

    /**
     * @notice Check if an address is frozen
     * @param wallet The wallet address
     * @return frozen True if frozen
     */
    function isFrozen(address wallet) external view returns (bool);

    /**
     * @notice Get the amount of frozen tokens for an address
     * @param wallet The wallet address
     * @return frozenAmount The amount of frozen tokens
     */
    function getFrozenTokens(address wallet) external view returns (uint256);

    /**
     * @notice Get token name
     * @return name The token name
     */
    function name() external view returns (string memory);

    /**
     * @notice Get token symbol
     * @return symbol The token symbol
     */
    function symbol() external view returns (string memory);

    /**
     * @notice Get token decimals
     * @return decimals The token decimals
     */
    function decimals() external view returns (uint8);
}
