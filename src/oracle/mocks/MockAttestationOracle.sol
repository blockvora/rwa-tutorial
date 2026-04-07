// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IAttestationOracle} from "../interfaces/IAttestationOracle.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title MockAttestationOracle
 * @notice Mock implementation of reserve attestation oracle for testing
 * @dev Simulates Chainlink Functions for off-chain reserve verification
 * 
 * In production, this would use Chainlink Functions to:
 * 1. Query brokerage APIs (Alpaca, Interactive Brokers, etc.)
 * 2. Verify custodian wallet balances
 * 3. Cryptographically prove reserves
 * 4. Return signed attestations
 * 
 * Example from rwa-creator (dTSLA):
 * - Chainlink Functions calls Alpaca API
 * - Verifies portfolio holds X shares of TSLA
 * - Returns portfolio balance to contract
 * - Contract uses this to enforce collateral ratio
 * 
 * This mock allows:
 * - Manual reserve updates for testing
 * - Simulation of async oracle responses
 * - Deterministic test scenarios
 */
contract MockAttestationOracle is IAttestationOracle, Ownable {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error MockAttestationOracle__InvalidAmount();
    error MockAttestationOracle__StaleData();

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    struct Attestation {
        uint256 amount; // Amount of reserves
        uint256 timestamp; // When attested
        string source; // Data source (e.g., "Alpaca API")
    }

    /// @notice Mapping of asset identifier to attestation
    /// @dev e.g., "TSLA" => Attestation(100e18, timestamp, "Alpaca")
    mapping(string => Attestation) private s_attestations;

    /// @notice Staleness threshold (3 hours, matching OracleLib)
    uint256 private constant STALENESS_THRESHOLD = 3 hours;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor() Ownable(msg.sender) {}

    /*//////////////////////////////////////////////////////////////
                           ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Update reserves for an asset (simulates Chainlink Functions callback)
     * @param asset The asset identifier (e.g., "TSLA", "USDC")
     * @param amount The amount of reserves
     * @param source The data source (e.g., "Alpaca API", "Custodian Wallet")
     * 
     * @dev In production, this would be called by Chainlink Functions
     * @dev For testing, owner can manually update reserves
     */
    function updateReserves(string memory asset, uint256 amount, string memory source) external onlyOwner {
        require(amount > 0, "MockAttestationOracle: invalid amount");

        s_attestations[asset] = Attestation({amount: amount, timestamp: block.timestamp, source: source});

        emit ReservesAttested(asset, amount, block.timestamp, source);
    }

    /**
     * @notice Simulate async oracle response (for testing)
     * @param asset The asset identifier
     * @param amount The amount of reserves
     * @param source The data source
     * @param delay Simulated delay in seconds
     * 
     * @dev Sets timestamp to (block.timestamp - delay) to simulate delayed response
     * @dev Useful for testing staleness checks
     */
    function updateReservesWithDelay(string memory asset, uint256 amount, string memory source, uint256 delay)
        external
        onlyOwner
    {
        require(amount > 0, "MockAttestationOracle: invalid amount");
        require(delay < block.timestamp, "MockAttestationOracle: invalid delay");

        uint256 attestationTime = block.timestamp - delay;
        s_attestations[asset] = Attestation({amount: amount, timestamp: attestationTime, source: source});

        emit ReservesAttested(asset, amount, attestationTime, source);
    }

    /*//////////////////////////////////////////////////////////////
                          ORACLE INTERFACE
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IAttestationOracle
     */
    function getReserves(string memory asset)
        external
        view
        override
        returns (uint256 amount, uint256 timestamp, bool isStale)
    {
        Attestation memory attestation = s_attestations[asset];
        
        // Check if data exists
        if (attestation.timestamp == 0) {
            return (0, 0, true);
        }

        // Check staleness
        uint256 age = block.timestamp - attestation.timestamp;
        isStale = age > STALENESS_THRESHOLD;

        return (attestation.amount, attestation.timestamp, isStale);
    }

    /**
     * @inheritdoc IAttestationOracle
     */
    function getStalenessThreshold() external pure override returns (uint256) {
        return STALENESS_THRESHOLD;
    }

    /**
     * @inheritdoc IAttestationOracle
     */
    function hasReserves(string memory asset, uint256 required) external view override returns (bool) {
        (uint256 amount, uint256 timestamp, bool isStale) = this.getReserves(asset);
        
        // Revert if data is stale
        if (isStale || timestamp == 0) {
            revert MockAttestationOracle__StaleData();
        }

        return amount >= required;
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get full attestation details
     * @param asset The asset identifier
     * @return amount The amount of reserves
     * @return timestamp When attested
     * @return source The data source
     */
    function getAttestation(string memory asset)
        external
        view
        returns (uint256 amount, uint256 timestamp, string memory source)
    {
        Attestation memory attestation = s_attestations[asset];
        return (attestation.amount, attestation.timestamp, attestation.source);
    }

    /**
     * @notice Check if reserves are sufficient (view function, doesn't revert)
     * @param asset The asset identifier
     * @param required The required amount
     * @return sufficient Whether reserves are sufficient
     * @return current The current reserve amount
     */
    function checkReserves(string memory asset, uint256 required)
        external
        view
        returns (bool sufficient, uint256 current)
    {
        (uint256 amount, uint256 timestamp, bool isStale) = this.getReserves(asset);
        
        // If stale or no data, not sufficient
        if (isStale || timestamp == 0) {
            return (false, 0);
        }

        return (amount >= required, amount);
    }

    /**
     * @notice Get the age of attestation data
     * @param asset The asset identifier
     * @return age Seconds since last attestation
     */
    function getDataAge(string memory asset) external view returns (uint256) {
        Attestation memory attestation = s_attestations[asset];
        if (attestation.timestamp == 0) {
            return type(uint256).max; // No data
        }
        return block.timestamp - attestation.timestamp;
    }
}
