// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

/**
 * @title IRedemptionManager
 * @notice Interface for managing async redemption of tokenized stocks
 * @dev Based on dTSLA patterns from rwa-creator
 * 
 * Flow:
 * 1. User calls requestRedemption() → burns tokens, creates request
 * 2. Oracle sells stock off-chain → receives USDC
 * 3. Oracle calls finalizeRedemption() → credits user's withdrawal balance
 * 4. User calls withdraw() → receives USDC
 */
interface IRedemptionManager {
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Emitted when a user requests redemption
     * @param requestId Unique identifier for the request
     * @param user The user requesting redemption
     * @param tokenAmount Amount of tokens to redeem
     * @param expectedUsdc Expected USDC amount (with slippage)
     */
    event RedemptionRequested(
        bytes32 indexed requestId, address indexed user, uint256 tokenAmount, uint256 expectedUsdc
    );

    /**
     * @notice Emitted when a redemption is finalized
     * @param requestId The request being fulfilled
     * @param user The user receiving funds
     * @param usdcAmount Amount of USDC credited
     */
    event RedemptionFulfilled(bytes32 indexed requestId, address indexed user, uint256 usdcAmount);

    /**
     * @notice Emitted when a user withdraws USDC
     * @param user The user withdrawing
     * @param amount Amount withdrawn
     */
    event Withdrawn(address indexed user, uint256 amount);

    /**
     * @notice Emitted when a redemption request is cancelled
     * @param requestId The cancelled request
     * @param user The user
     */
    event RedemptionCancelled(bytes32 indexed requestId, address indexed user);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error RedemptionManager__BelowMinimum();
    error RedemptionManager__InsufficientBalance();
    error RedemptionManager__RequestNotFound();
    error RedemptionManager__RequestAlreadyFulfilled();
    error RedemptionManager__RequestNotExpired();
    error RedemptionManager__RequestExpired();
    error RedemptionManager__SlippageExceeded();
    error RedemptionManager__NoWithdrawalBalance();
    error RedemptionManager__TransferFailed();
    error RedemptionManager__InsufficientContractBalance();

    /*//////////////////////////////////////////////////////////////
                            USER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Request redemption of tokens for USDC
     * @param tokenAmount Amount of tokens to redeem
     * @return requestId Unique identifier for tracking
     * 
     * @dev Burns tokens immediately, creates pending request
     * @dev Oracle will fulfill request off-chain
     */
    function requestRedemption(uint256 tokenAmount) external returns (bytes32 requestId);

    /**
     * @notice Withdraw available USDC balance
     * @return amount Amount withdrawn
     * 
     * @dev Transfers all available USDC to caller
     */
    function withdraw() external returns (uint256 amount);

    /**
     * @notice Cancel an expired redemption request
     * @param requestId The request to cancel
     * 
     * @dev Only works if request is expired and not fulfilled
     * @dev Refunds tokens to user
     */
    function cancelRedemption(bytes32 requestId) external;

    /*//////////////////////////////////////////////////////////////
                           ORACLE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Finalize a redemption request (oracle only)
     * @param requestId The request to fulfill
     * @param usdcAmount Amount of USDC received from sale
     * 
     * @dev Called by oracle after selling stock off-chain
     * @dev Credits user's withdrawal balance
     */
    function finalizeRedemption(bytes32 requestId, uint256 usdcAmount) external;

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get user's available withdrawal balance
     * @param user The user address
     * @return balance Available USDC balance
     */
    function getWithdrawalBalance(address user) external view returns (uint256 balance);

    /**
     * @notice Get redemption request details
     * @param requestId The request ID
     * @return user The requester
     * @return tokenAmount Amount of tokens
     * @return expectedUsdc Expected USDC amount
     * @return timestamp When requested
     * @return fulfilled Whether fulfilled
     */
    function getRedemptionRequest(bytes32 requestId)
        external
        view
        returns (address user, uint256 tokenAmount, uint256 expectedUsdc, uint256 timestamp, bool fulfilled);

    /**
     * @notice Check if a request is expired
     * @param requestId The request ID
     * @return expired Whether the request has expired
     */
    function isRequestExpired(bytes32 requestId) external view returns (bool expired);

    /**
     * @notice Get minimum redemption amount
     * @return minimum Minimum tokens required
     */
    function getMinimumRedemption() external view returns (uint256 minimum);

    /**
     * @notice Get redemption expiry time
     * @return expiry Time in seconds before request expires
     */
    function getRedemptionExpiry() external view returns (uint256 expiry);
}
