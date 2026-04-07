// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

/**
 * @title IAttestationOracle
 * @notice Interface for reserve/custody attestation oracle
 * @dev Simulates Chainlink Functions for off-chain reserve verification
 * 
 * In production, this would use Chainlink Functions to:
 * - Query brokerage APIs (e.g., Alpaca, Interactive Brokers)
 * - Verify custodian balances
 * - Cryptographically prove reserves
 * 
 * For this tutorial, we mock the behavior for testing.
 */
interface IAttestationOracle {
    /**
     * @notice Emitted when reserves are updated
     * @param asset The asset being attested (e.g., "TSLA")
     * @param amount The amount of reserves
     * @param timestamp When the attestation was made
     * @param source The data source (e.g., "Alpaca API")
     */
    event ReservesAttested(string indexed asset, uint256 amount, uint256 timestamp, string source);

    /**
     * @notice Get the current attested reserves for an asset
     * @param asset The asset identifier (e.g., "TSLA", "USDC")
     * @return amount The amount of reserves held
     * @return timestamp When this was last verified
     * @return isStale Whether the data is considered stale
     */
    function getReserves(string memory asset)
        external
        view
        returns (uint256 amount, uint256 timestamp, bool isStale);

    /**
     * @notice Get the staleness threshold
     * @return timeout Seconds after which data is considered stale
     */
    function getStalenessThreshold() external view returns (uint256);

    /**
     * @notice Check if reserves are sufficient for a given requirement
     * @param asset The asset to check
     * @param required The required amount
     * @return sufficient Whether reserves meet the requirement
     */
    function hasReserves(string memory asset, uint256 required) external view returns (bool);
}
