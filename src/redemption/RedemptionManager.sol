// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IRedemptionManager} from "./interfaces/IRedemptionManager.sol";
import {IStockToken} from "../token/interfaces/IStockToken.sol";
import {IPriceOracle} from "../oracle/interfaces/IPriceOracle.sol";
import {OracleLib} from "../oracle/libraries/OracleLib.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title RedemptionManager
 * @notice Manages async redemption of tokenized stocks for USDC
 * @dev Based on dTSLA patterns from rwa-creator
 * 
 * Why Async?
 * - Blockchain transactions are synchronous (must complete in one block)
 * - Selling stocks requires off-chain API calls to brokerages
 * - Stock settlement takes time (T+2 for traditional markets)
 * - USDC conversion happens off-chain
 * 
 * Flow:
 * 1. User requests redemption → tokens burned immediately
 * 2. Oracle sells stock off-chain → receives USD
 * 3. Oracle converts to USDC → sends to contract
 * 4. Oracle finalizes redemption → credits user's withdrawal balance
 * 5. User withdraws USDC → receives funds
 */
contract RedemptionManager is IRedemptionManager, AccessControl, ReentrancyGuard {
    using OracleLib for IPriceOracle;

    /*//////////////////////////////////////////////////////////////
                                 ROLES
    //////////////////////////////////////////////////////////////*/

    bytes32 public constant ORACLE_ROLE = keccak256("ORACLE_ROLE");

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    struct RedemptionRequest {
        address user;
        uint256 tokenAmount;
        uint256 expectedUsdc; // Expected USDC with slippage tolerance
        uint256 timestamp;
        bool fulfilled;
    }

    /// @notice The stock token being redeemed
    IStockToken public immutable i_stockToken;

    /// @notice The USDC token received from redemptions
    IERC20 public immutable i_usdc;

    /// @notice Price oracle for stock/USD
    IPriceOracle public immutable i_stockPriceOracle;

    /// @notice Price oracle for USDC/USD
    IPriceOracle public immutable i_usdcPriceOracle;

    /// @notice Minimum redemption amount (e.g., $100 worth)
    uint256 public immutable i_minimumRedemption;

    /// @notice Maximum slippage tolerance (basis points, e.g., 200 = 2%)
    uint256 public constant MAX_SLIPPAGE_BPS = 200;

    /// @notice Basis points precision
    uint256 public constant BPS_PRECISION = 10000;

    /// @notice Time before request expires (7 days)
    uint256 public constant REDEMPTION_EXPIRY = 7 days;

    /// @notice Mapping of request ID to redemption request
    mapping(bytes32 => RedemptionRequest) private s_redemptionRequests;

    /// @notice Mapping of user to withdrawal balance
    mapping(address => uint256) private s_withdrawalBalance;

    /// @notice Mapping of user to their request IDs
    mapping(address => bytes32[]) private s_userRequests;

    /// @notice Counter for generating unique request IDs
    uint256 private s_requestCounter;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initialize the redemption manager
     * @param stockToken The token being redeemed
     * @param usdc The USDC token
     * @param stockPriceOracle Price oracle for stock
     * @param usdcPriceOracle Price oracle for USDC
     * @param minimumRedemption Minimum redemption amount in USDC (18 decimals)
     */
    constructor(
        address stockToken,
        address usdc,
        address stockPriceOracle,
        address usdcPriceOracle,
        uint256 minimumRedemption
    ) {
        require(stockToken != address(0), "RedemptionManager: invalid stock token");
        require(usdc != address(0), "RedemptionManager: invalid USDC");
        require(stockPriceOracle != address(0), "RedemptionManager: invalid stock oracle");
        require(usdcPriceOracle != address(0), "RedemptionManager: invalid USDC oracle");
        require(minimumRedemption > 0, "RedemptionManager: invalid minimum");

        i_stockToken = IStockToken(stockToken);
        i_usdc = IERC20(usdc);
        i_stockPriceOracle = IPriceOracle(stockPriceOracle);
        i_usdcPriceOracle = IPriceOracle(usdcPriceOracle);
        i_minimumRedemption = minimumRedemption;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ORACLE_ROLE, msg.sender);
    }

    /*//////////////////////////////////////////////////////////////
                            USER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IRedemptionManager
     */
    function requestRedemption(uint256 tokenAmount) external override nonReentrant returns (bytes32 requestId) {
        // Calculate expected USDC amount
        uint256 stockPrice = i_stockPriceOracle.getPrice();
        uint256 usdcPrice = i_usdcPriceOracle.getPrice();

        // Token value in USD (18 decimals)
        uint256 tokenValueUsd = (tokenAmount * stockPrice) / 1e18;

        // Convert to USDC amount (18 decimals)
        uint256 expectedUsdc = (tokenValueUsd * 1e18) / usdcPrice;

        // Check minimum
        if (expectedUsdc < i_minimumRedemption) {
            revert RedemptionManager__BelowMinimum();
        }

        // Check user balance
        if (i_stockToken.balanceOf(msg.sender) < tokenAmount) {
            revert RedemptionManager__InsufficientBalance();
        }

        // Generate unique request ID
        requestId = keccak256(abi.encodePacked(msg.sender, tokenAmount, block.timestamp, s_requestCounter++));

        // Store request
        s_redemptionRequests[requestId] = RedemptionRequest({
            user: msg.sender,
            tokenAmount: tokenAmount,
            expectedUsdc: expectedUsdc,
            timestamp: block.timestamp,
            fulfilled: false
        });

        // Track user's requests (for querying)
        s_userRequests[msg.sender].push(requestId);

        // Burn tokens immediately (prevents double-spending)
        i_stockToken.burn(msg.sender, tokenAmount);

        emit RedemptionRequested(requestId, msg.sender, tokenAmount, expectedUsdc);

        return requestId;
    }

    /**
     * @inheritdoc IRedemptionManager
     */
    function withdraw() external override nonReentrant returns (uint256 amount) {
        amount = s_withdrawalBalance[msg.sender];

        if (amount == 0) {
            revert RedemptionManager__NoWithdrawalBalance();
        }

        // Clear balance before transfer (CEI pattern)
        s_withdrawalBalance[msg.sender] = 0;

        // Convert from 18 decimals (internal) to USDC decimals (6)
        uint256 usdcAmount = _convertTo6Decimals(amount);

        // Transfer USDC
        bool success = i_usdc.transfer(msg.sender, usdcAmount);
        if (!success) {
            revert RedemptionManager__TransferFailed();
        }

        emit Withdrawn(msg.sender, amount);

        return amount;
    }

    /**
     * @inheritdoc IRedemptionManager
     */
    function cancelRedemption(bytes32 requestId) external override nonReentrant {
        RedemptionRequest storage request = s_redemptionRequests[requestId];

        // Validate request
        if (request.user == address(0)) {
            revert RedemptionManager__RequestNotFound();
        }

        if (request.user != msg.sender) {
            revert RedemptionManager__RequestNotFound(); // Don't reveal existence
        }

        if (request.fulfilled) {
            revert RedemptionManager__RequestAlreadyFulfilled();
        }

        if (!isRequestExpired(requestId)) {
            revert RedemptionManager__RequestNotExpired();
        }

        // Mark as fulfilled to prevent re-cancellation
        request.fulfilled = true;

        // Refund tokens (mint back)
        i_stockToken.mint(msg.sender, request.tokenAmount);

        emit RedemptionCancelled(requestId, msg.sender);
    }

    /*//////////////////////////////////////////////////////////////
                           ORACLE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IRedemptionManager
     */
    function finalizeRedemption(bytes32 requestId, uint256 usdcAmount)
        external
        override
        onlyRole(ORACLE_ROLE)
        nonReentrant
    {
        RedemptionRequest storage request = s_redemptionRequests[requestId];

        // Validate request
        if (request.user == address(0)) {
            revert RedemptionManager__RequestNotFound();
        }

        if (request.fulfilled) {
            revert RedemptionManager__RequestAlreadyFulfilled();
        }

        // Check request hasn't expired (prevent double-redemption via cancel)
        if (isRequestExpired(requestId)) {
            revert RedemptionManager__RequestExpired();
        }

        // Check slippage (allow up to MAX_SLIPPAGE_BPS deviation)
        uint256 minAcceptable = (request.expectedUsdc * (BPS_PRECISION - MAX_SLIPPAGE_BPS)) / BPS_PRECISION;
        if (usdcAmount < minAcceptable) {
            revert RedemptionManager__SlippageExceeded();
        }

        // CRITICAL: Verify contract has sufficient USDC before crediting
        // In production, this should be checked against total pending withdrawals
        uint256 contractBalance = i_usdc.balanceOf(address(this));
        uint256 usdcAmount6Decimals = _convertTo6Decimals(usdcAmount);
        if (contractBalance < usdcAmount6Decimals) {
            revert RedemptionManager__InsufficientContractBalance();
        }

        // Mark as fulfilled
        request.fulfilled = true;

        // Credit user's withdrawal balance
        s_withdrawalBalance[request.user] += usdcAmount;

        emit RedemptionFulfilled(requestId, request.user, usdcAmount);
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IRedemptionManager
     */
    function getWithdrawalBalance(address user) external view override returns (uint256 balance) {
        return s_withdrawalBalance[user];
    }

    /**
     * @inheritdoc IRedemptionManager
     */
    function getRedemptionRequest(bytes32 requestId)
        external
        view
        override
        returns (address user, uint256 tokenAmount, uint256 expectedUsdc, uint256 timestamp, bool fulfilled)
    {
        RedemptionRequest memory request = s_redemptionRequests[requestId];
        return (request.user, request.tokenAmount, request.expectedUsdc, request.timestamp, request.fulfilled);
    }

    /**
     * @inheritdoc IRedemptionManager
     */
    function isRequestExpired(bytes32 requestId) public view override returns (bool expired) {
        RedemptionRequest memory request = s_redemptionRequests[requestId];
        if (request.user == address(0)) return false;
        return block.timestamp > request.timestamp + REDEMPTION_EXPIRY;
    }

    /**
     * @inheritdoc IRedemptionManager
     */
    function getMinimumRedemption() external view override returns (uint256 minimum) {
        return i_minimumRedemption;
    }

    /**
     * @inheritdoc IRedemptionManager
     */
    function getRedemptionExpiry() external pure override returns (uint256 expiry) {
        return REDEMPTION_EXPIRY;
    }

    /**
     * @notice Get all request IDs for a user
     * @param user The user address
     * @return requestIds Array of request IDs
     * 
     * @dev Includes both pending and fulfilled requests
     * @dev Use getRedemptionRequest() to check status of each
     */
    function getUserRequests(address user) external view returns (bytes32[] memory) {
        return s_userRequests[user];
    }

    /**
     * @notice Get pending (unfulfilled) requests for a user
     * @param user The user address
     * @return pendingRequests Array of pending request IDs
     */
    function getPendingRequests(address user) external view returns (bytes32[] memory) {
        bytes32[] memory allRequests = s_userRequests[user];
        uint256 pendingCount = 0;

        // Count pending requests
        for (uint256 i = 0; i < allRequests.length; i++) {
            if (!s_redemptionRequests[allRequests[i]].fulfilled) {
                pendingCount++;
            }
        }

        // Build pending array
        bytes32[] memory pending = new bytes32[](pendingCount);
        uint256 index = 0;
        for (uint256 i = 0; i < allRequests.length; i++) {
            if (!s_redemptionRequests[allRequests[i]].fulfilled) {
                pending[index++] = allRequests[i];
            }
        }

        return pending;
    }

    /*//////////////////////////////////////////////////////////////
                           INTERNAL HELPERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Convert from 18 decimals (internal accounting) to 6 decimals (USDC)
     * @param amount Amount in 18 decimals
     * @return Amount in 6 decimals (rounded up to favor user)
     * 
     * @dev Rounds up to ensure users never lose value due to precision
     * @dev Example: 1.999999999999999999 (18 dec) → 2.000000 (6 dec), not 1.999999
     * @dev This is fair because:
     *      - User burned exact token amount
     *      - Oracle received exact USD amount
     *      - Rounding error is negligible (<$0.000001)
     *      - Better to slightly overpay than underpay users
     */
    function _convertTo6Decimals(uint256 amount) internal pure returns (uint256) {
        // Round up: (amount + (1e12 - 1)) / 1e12
        // This ensures any fractional amount rounds up to next whole unit
        return (amount + 1e12 - 1) / 1e12;
    }
}
