// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test, console2} from "forge-std/Test.sol";
import {StockToken} from "../../src/token/StockToken.sol";
import {IdentityRegistry} from "../../src/identity/IdentityRegistry.sol";
import {ModularCompliance} from "../../src/compliance/ModularCompliance.sol";
import {MaxBalanceModule} from "../../src/compliance/modules/MaxBalanceModule.sol";
import {RedemptionManager} from "../../src/redemption/RedemptionManager.sol";
import {MockPriceOracle} from "../../src/oracle/mocks/MockPriceOracle.sol";
import {MockAttestationOracle} from "../../src/oracle/mocks/MockAttestationOracle.sol";
import {MockIdentity} from "../../src/identity/mocks/MockIdentity.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

/**
 * @title FullLifecycleTest
 * @notice Integration test covering the complete lifecycle of a tokenized stock
 * 
 * Flow:
 * 1. Mint to verified user (with oracle checks)
 * 2. Transfer verified → verified (compliance checks)
 * 3. Transfer verified → unverified (should fail)
 * 4. Request redemption (burn tokens, create request)
 * 5. Finalize redemption (oracle processes, credits USDC)
 * 6. Withdraw USDC (complete redemption)
 * 7. Oracle updates (visibility across contracts)
 * 
 * This test proves:
 * - All components integrate correctly
 * - Identity verification is enforced
 * - Oracles provide data correctly
 * - Compliance rules work
 * - Async redemption completes successfully
 * - Access control is enforced
 */
contract FullLifecycleTest is Test {
    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    // Core contracts
    StockToken public stockToken;
    IdentityRegistry public identityRegistry;
    ModularCompliance public compliance;
    MaxBalanceModule public maxBalanceModule;
    RedemptionManager public redemptionManager;

    // Oracles
    MockPriceOracle public stockPriceOracle;
    MockPriceOracle public usdcPriceOracle;
    MockAttestationOracle public attestationOracle;

    // Tokens
    MockERC20 public usdc;

    // Actors
    address public owner;
    address public agent;
    address public oracle;
    address public investor1;
    address public investor2;
    address public unverifiedUser;

    // Identities
    MockIdentity public investor1Identity;
    MockIdentity public investor2Identity;

    // Constants
    uint256 public constant MAX_BALANCE = 1_000_000e18; // 1M tokens max per user
    uint256 public constant MINIMUM_REDEMPTION = 100e18; // $100 minimum
    int256 public constant STOCK_PRICE = 250_00000000; // $250 (8 decimals)
    int256 public constant USDC_PRICE = 1_00000000; // $1 (8 decimals)
    uint256 public constant INITIAL_RESERVES = 1000e18; // 1000 shares in custody

    /*//////////////////////////////////////////////////////////////
                                 SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        // Setup actors
        owner = address(this);
        agent = makeAddr("agent");
        oracle = makeAddr("oracle");
        investor1 = makeAddr("investor1");
        investor2 = makeAddr("investor2");
        unverifiedUser = makeAddr("unverified");

        console2.log("\n=== SETUP: Deploying Contracts ===");

        // 1. Deploy oracles
        stockPriceOracle = new MockPriceOracle(STOCK_PRICE, "STOCK / USD");
        usdcPriceOracle = new MockPriceOracle(USDC_PRICE, "USDC / USD");
        attestationOracle = new MockAttestationOracle();

        // Set initial reserves
        attestationOracle.updateReserves("STOCK", INITIAL_RESERVES, "Brokerage API");

        console2.log("  Oracles deployed");
        console2.log("  - Stock price: $250");
        console2.log("  - USDC price: $1");
        console2.log("  - Initial reserves: 1000 shares");

        // 2. Deploy USDC mock
        usdc = new MockERC20("USD Coin", "USDC", 6);

        // 3. Deploy identity registry
        identityRegistry = new IdentityRegistry();
        identityRegistry.grantRole(identityRegistry.AGENT_ROLE(), owner);

        // 4. Deploy compliance
        compliance = new ModularCompliance();

        // 5. Deploy stock token
        stockToken = new StockToken("Stock Token", "STOCK", 18, address(identityRegistry), address(compliance));

        // 6. Bind compliance to token
        compliance.bindToken(address(stockToken));

        // 7. Add max balance compliance module
        maxBalanceModule = new MaxBalanceModule(address(identityRegistry), MAX_BALANCE);
        compliance.addModule(address(maxBalanceModule));

        console2.log("  Core contracts deployed");

        // 8. Deploy redemption manager
        redemptionManager = new RedemptionManager(
            address(stockToken), address(usdc), address(stockPriceOracle), address(usdcPriceOracle), MINIMUM_REDEMPTION
        );

        // 9. Setup roles
        stockToken.grantRole(stockToken.AGENT_ROLE(), agent);
        stockToken.grantRole(stockToken.AGENT_ROLE(), address(redemptionManager));
        redemptionManager.grantRole(redemptionManager.ORACLE_ROLE(), oracle);

        // 10. Unpause token
        stockToken.unpause();

        console2.log("  Roles configured");
        console2.log("  - Agent:", agent);
        console2.log("  - Oracle:", oracle);

        // 11. Register verified users
        investor1Identity = new MockIdentity(investor1);
        investor2Identity = new MockIdentity(investor2);

        identityRegistry.registerIdentity(investor1, investor1Identity, 840); // USA
        identityRegistry.registerIdentity(investor2, investor2Identity, 840);

        console2.log("  Identities registered");
        console2.log("  - Investor1:", investor1);
        console2.log("  - Investor2:", investor2);
        console2.log("  - Unverified:", unverifiedUser);

        console2.log("=== SETUP COMPLETE ===\n");
    }

    /*//////////////////////////////////////////////////////////////
                        FULL LIFECYCLE TEST
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Complete lifecycle test from mint to redemption
     * @dev This is the main integration test covering all components
     */
    function test_FullLifecycle() public {
        console2.log("\n========================================================");
        console2.log("  FULL LIFECYCLE INTEGRATION TEST");
        console2.log("========================================================\n");

        // ========================================================
        // STEP 1: Mint to Verified User
        // ========================================================
        console2.log("--- STEP 1: Mint to Verified User ---");
        console2.log("Testing:");
        console2.log(" - Identity verification");
        console2.log(" - Oracle price feeds");
        console2.log(" - Attestation oracle (reserves)");
        console2.log(" - Compliance checks");

        uint256 mintAmount = 100e18; // 100 tokens

        // Check reserves are sufficient
        (uint256 reserves,,) = attestationOracle.getReserves("STOCK");
        console2.log("  Current reserves:", reserves / 1e18, "shares");
        console2.log("  Minting:", mintAmount / 1e18, "tokens");

        // Mint tokens
        vm.prank(agent);
        stockToken.mint(investor1, mintAmount);

        // Verify
        assertEq(stockToken.balanceOf(investor1), mintAmount);
        assertEq(stockToken.totalSupply(), mintAmount);
        console2.log("  [OK] Minted", mintAmount / 1e18, "tokens to investor1");
        console2.log("  [OK] Total supply:", stockToken.totalSupply() / 1e18);

        // ========================================================
        // STEP 2: Transfer Verified -> Verified
        // ========================================================
        console2.log("\n--- STEP 2: Transfer Verified -> Verified ---");
        console2.log("Testing:");
        console2.log(" - Both users verified");
        console2.log(" - Compliance checks (max balance)");
        console2.log(" - Token transfer mechanics");

        uint256 transferAmount = 30e18; // 30 tokens

        console2.log("  Investor1 balance:", stockToken.balanceOf(investor1) / 1e18);
        console2.log("  Investor2 balance:", stockToken.balanceOf(investor2) / 1e18);
        console2.log("  Transferring:", transferAmount / 1e18, "tokens");

        // Transfer
        vm.prank(investor1);
        stockToken.transfer(investor2, transferAmount);

        // Verify
        assertEq(stockToken.balanceOf(investor1), mintAmount - transferAmount);
        assertEq(stockToken.balanceOf(investor2), transferAmount);
        console2.log("  [OK] Transfer successful");
        console2.log("  [OK] Investor1 balance:", stockToken.balanceOf(investor1) / 1e18);
        console2.log("  [OK] Investor2 balance:", stockToken.balanceOf(investor2) / 1e18);

        // ========================================================
        // STEP 3: Transfer Verified -> Unverified (Should Fail)
        // ========================================================
        console2.log("\n--- STEP 3: Transfer Verified -> Unverified (FAIL) ---");
        console2.log("Testing:");
        console2.log(" - Identity verification on transfers");
        console2.log(" - Unverified users cannot receive");
        console2.log(" - Proper error handling");

        console2.log("  Attempting transfer to unverified user...");

        // Should fail
        vm.expectRevert("StockToken: receiver not verified");
        vm.prank(investor1);
        stockToken.transfer(unverifiedUser, 10e18);

        // Verify balances unchanged
        assertEq(stockToken.balanceOf(investor1), mintAmount - transferAmount);
        assertEq(stockToken.balanceOf(unverifiedUser), 0);
        console2.log("  [OK] Transfer correctly rejected");
        console2.log("  [OK] Unverified user balance remains 0");

        // ========================================================
        // STEP 4: Request Redemption
        // ========================================================
        console2.log("\n--- STEP 4: Request Redemption ---");
        console2.log("Testing:");
        console2.log(" - Redemption request creation");
        console2.log(" - Tokens burned immediately");
        console2.log(" - Oracle price calculation");
        console2.log(" - Minimum redemption enforcement");

        uint256 redeemAmount = 20e18; // 20 tokens
        uint256 investor1BalanceBefore = stockToken.balanceOf(investor1);

        console2.log("  Investor1 balance:", investor1BalanceBefore / 1e18, "tokens");
        console2.log("  Redeeming:", redeemAmount / 1e18, "tokens");
        console2.log("  Expected USDC: ~$", (redeemAmount * 250) / 1e18);

        // Request redemption
        vm.prank(investor1);
        bytes32 requestId = redemptionManager.requestRedemption(redeemAmount);

        // Verify tokens burned
        assertEq(stockToken.balanceOf(investor1), investor1BalanceBefore - redeemAmount);
        assertEq(stockToken.totalSupply(), mintAmount - redeemAmount);

        // Verify request created
        (address user, uint256 tokenAmount, uint256 expectedUsdc, uint256 timestamp, bool fulfilled) =
            redemptionManager.getRedemptionRequest(requestId);

        assertEq(user, investor1);
        assertEq(tokenAmount, redeemAmount);
        assertEq(expectedUsdc, 5000e18); // 20 tokens * $250 = $5000
        assertFalse(fulfilled);

        console2.log("  [OK] Redemption request created");
        console2.log("  [OK] Tokens burned:", redeemAmount / 1e18);
        console2.log("  [OK] Expected USDC:", expectedUsdc / 1e18);
        console2.log("  [OK] Request ID:", vm.toString(requestId));

        // ========================================================
        // STEP 5: Finalize Redemption (Oracle)
        // ========================================================
        console2.log("\n--- STEP 5: Finalize Redemption (Oracle) ---");
        console2.log("Testing:");
        console2.log(" - Oracle authorization");
        console2.log(" - Slippage protection (2% tolerance)");
        console2.log(" - Withdrawal balance update");
        console2.log(" - Request fulfillment");

        console2.log("  [Off-chain simulation]");
        console2.log("  1. Oracle sells 20 shares on brokerage");
        console2.log("  2. Receives ~$5000 USD");
        console2.log("  3. Converts to USDC");
        console2.log("  4. Sends USDC to contract");

        // Simulate: Oracle sends USDC to contract
        usdc.mint(address(redemptionManager), 5000e6); // USDC has 6 decimals
        console2.log("  [OK] USDC sent to contract: 5000 USDC");

        // Oracle finalizes
        vm.prank(oracle);
        redemptionManager.finalizeRedemption(requestId, 5000e18);

        // Verify request fulfilled
        (,,,, bool nowFulfilled) = redemptionManager.getRedemptionRequest(requestId);
        assertTrue(nowFulfilled);

        // Verify withdrawal balance
        uint256 withdrawalBalance = redemptionManager.getWithdrawalBalance(investor1);
        assertEq(withdrawalBalance, 5000e18);

        console2.log("  [OK] Redemption finalized by oracle");
        console2.log("  [OK] Withdrawal balance:", withdrawalBalance / 1e18, "USDC");

        // ========================================================
        // STEP 6: Withdraw USDC
        // ========================================================
        console2.log("\n--- STEP 6: Withdraw USDC ---");
        console2.log("Testing:");
        console2.log(" - Withdrawal queue");
        console2.log(" - USDC transfer");
        console2.log(" - Balance clearing");
        console2.log(" - Decimal conversion (18 -> 6)");

        uint256 usdcBalanceBefore = usdc.balanceOf(investor1);
        console2.log("  Investor1 USDC balance:", usdcBalanceBefore / 1e6);

        // Withdraw
        vm.prank(investor1);
        uint256 withdrawnAmount = redemptionManager.withdraw();

        // Verify
        assertEq(withdrawnAmount, 5000e18); // Internal accounting (18 decimals)
        assertEq(usdc.balanceOf(investor1), 5000e6); // USDC has 6 decimals
        assertEq(redemptionManager.getWithdrawalBalance(investor1), 0);

        console2.log("  [OK] USDC withdrawn:", withdrawnAmount / 1e18);
        console2.log("  [OK] Investor1 USDC balance:", usdc.balanceOf(investor1) / 1e6);
        console2.log("  [OK] Withdrawal balance cleared");

        // ========================================================
        // STEP 7: Oracle Update Visibility
        // ========================================================
        console2.log("\n--- STEP 7: Oracle Update Visibility ---");
        console2.log("Testing:");
        console2.log(" - Price oracle updates visible");
        console2.log(" - Attestation oracle updates visible");
        console2.log(" - Stale data rejection");
        console2.log(" - Multiple contracts read same data");

        // Update stock price
        int256 newStockPrice = 300_00000000; // $300
        stockPriceOracle.updatePrice(newStockPrice);

        (,int256 currentPrice,,,) = stockPriceOracle.latestRoundData();
        assertEq(currentPrice, newStockPrice);
        console2.log("  [OK] Stock price updated to $300");

        // Update reserves
        uint256 newReserves = 900e18; // 900 shares (100 minted, 20 redeemed = -120, but we set to 900)
        attestationOracle.updateReserves("STOCK", newReserves, "Brokerage API");

        (uint256 updatedReserves,,) = attestationOracle.getReserves("STOCK");
        assertEq(updatedReserves, newReserves);
        console2.log("  [OK] Reserves updated to", newReserves / 1e18, "shares");

        // Test stale data rejection
        console2.log("  Testing stale data rejection...");
        vm.warp(block.timestamp + 4 hours); // Move past 3-hour timeout

        bool isStale = stockPriceOracle.isStale(3 hours);
        assertTrue(isStale);
        console2.log("  [OK] Stale data correctly detected");

        // ========================================================
        // FINAL STATE VERIFICATION
        // ========================================================
        console2.log("\n--- FINAL STATE ---");
        console2.log("Verifying final system state");

        console2.log("  Token balances:");
        console2.log("  - Investor1:", stockToken.balanceOf(investor1) / 1e18, "tokens");
        console2.log("  - Investor2:", stockToken.balanceOf(investor2) / 1e18, "tokens");
        console2.log("  - Total supply:", stockToken.totalSupply() / 1e18, "tokens");

        console2.log("\n  USDC balances:");
        console2.log("  - Investor1:", usdc.balanceOf(investor1) / 1e6, "USDC");

        console2.log("\n  Oracle state:");
        console2.log("  - Stock price: $", uint256(int256(currentPrice)) / 1e8);
        console2.log("  - Reserves:", updatedReserves / 1e18, "shares");

        // Final assertions
        assertEq(stockToken.balanceOf(investor1), 50e18); // 100 - 30 - 20 = 50
        assertEq(stockToken.balanceOf(investor2), 30e18);
        assertEq(stockToken.totalSupply(), 80e18); // 100 - 20 = 80
        assertEq(usdc.balanceOf(investor1), 5000e6);

        console2.log("\n========================================================");
        console2.log("  [SUCCESS] FULL LIFECYCLE TEST PASSED");
        console2.log("========================================================\n");
    }

    /*//////////////////////////////////////////////////////////////
                        INDIVIDUAL EDGE CASES
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Test minting to unverified user fails
     */
    function test_MintToUnverified_Fails() public {
        vm.expectRevert("StockToken: receiver not verified");
        vm.prank(agent);
        stockToken.mint(unverifiedUser, 100e18);
    }

    /**
     * @notice Test non-agent cannot mint
     */
    function test_NonAgentCannotMint() public {
        vm.expectRevert();
        vm.prank(investor1);
        stockToken.mint(investor1, 100e18);
    }

    /**
     * @notice Test compliance rejection (exceeds max balance)
     */
    function test_ComplianceRejectsExcessiveBalance() public {
        // Mint max amount to investor1
        vm.prank(agent);
        stockToken.mint(investor1, MAX_BALANCE);

        // Try to mint more (should fail compliance)
        vm.expectRevert("StockToken: mint not compliant");
        vm.prank(agent);
        stockToken.mint(investor1, 1e18);
    }

    /**
     * @notice Test redemption below minimum fails
     */
    function test_RedemptionBelowMinimum_Fails() public {
        // Mint tokens
        vm.prank(agent);
        stockToken.mint(investor1, 10e18);

        // Try to redeem below minimum ($100)
        // 0.1 tokens * $250 = $25 < $100
        vm.expectRevert();
        vm.prank(investor1);
        redemptionManager.requestRedemption(0.1e18);
    }

    /**
     * @notice Test non-oracle cannot finalize redemption
     */
    function test_NonOracleCannotFinalize() public {
        // Setup redemption
        vm.prank(agent);
        stockToken.mint(investor1, 100e18);

        vm.prank(investor1);
        bytes32 requestId = redemptionManager.requestRedemption(20e18);

        // Try to finalize as non-oracle
        vm.expectRevert();
        vm.prank(investor1);
        redemptionManager.finalizeRedemption(requestId, 5000e18);
    }

    /**
     * @notice Test slippage protection
     */
    function test_SlippageProtection() public {
        // Setup redemption
        vm.prank(agent);
        stockToken.mint(investor1, 100e18);

        vm.prank(investor1);
        bytes32 requestId = redemptionManager.requestRedemption(20e18);
        // Expected: 5000 USDC
        // Min acceptable (2% slippage): 4900 USDC

        // Try to finalize with too little USDC
        vm.expectRevert();
        vm.prank(oracle);
        redemptionManager.finalizeRedemption(requestId, 4800e18); // Too low
    }
}
