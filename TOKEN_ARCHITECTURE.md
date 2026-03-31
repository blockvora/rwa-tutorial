// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

/**
 * TOKEN ARCHITECTURE: Permissioned Stock Token
 * 
 * This document explains the StockToken implementation that combines:
 * - ERC-3643 (identity verification + compliance enforcement)
 * - RWA lifecycle (mint, transfer, burn, redemption)
 * 
 * ============================================================================
 * ARCHITECTURE OVERVIEW
 * ============================================================================
 * 
 * StockToken integrates three core systems:
 * 
 * 1. Identity System (IdentityRegistry)
 *    - Verifies investor eligibility
 *    - Maps wallets to ONCHAINID contracts
 *    - Checks KYC/accreditation status
 * 
 * 2. Compliance System (ModularCompliance)
 *    - Enforces regulatory rules
 *    - Pluggable modules (max balance, transfer limits, etc.)
 *    - Tracks state across transfers
 * 
 * 3. Token System (StockToken)
 *    - ERC20 base functionality
 *    - Permissioned transfers
 *    - Agent controls (mint, burn, freeze)
 *    - Redemption requests
 * 
 * ┌─────────────────────────────────────────────────────────────┐
 * │                      StockToken                             │
 * │  - ERC20 balances & transfers                               │
 * │  - Pause/freeze controls                                    │
 * │  - Agent-only mint/burn                                     │
 * │  - Redemption requests                                      │
 * └─────────────────────────────────────────────────────────────┘
 *                 │                           │
 *                 ▼                           ▼
 * ┌───────────────────────────┐   ┌───────────────────────────┐
 * │   IdentityRegistry        │   │   ModularCompliance       │
 * │  - Wallet verification    │   │  - Rule orchestration     │
 * │  - ONCHAINID mapping      │   │  - Module iteration       │
 * │  - Claim checking         │   │  - State updates          │
 * └───────────────────────────┘   └───────────────────────────┘
 * 
 * ============================================================================
 * TRANSFER FLOW (Step-by-Step)
 * ============================================================================
 * 
 * When investor1.transfer(investor2, 100 tokens):
 * 
 * 1. CHECK: Token not paused
 *    └─ Revert if paused (emergency stop)
 * 
 * 2. CHECK: Sender and receiver not frozen
 *    └─ Revert if either address is frozen (regulatory action)
 * 
 * 3. CHECK: Sender has sufficient unfrozen balance
 *    └─ balance - frozenTokens >= amount
 *    └─ Revert if trying to transfer frozen tokens
 * 
 * 4. CHECK: Receiver is verified
 *    └─ identityRegistry.isVerified(receiver)
 *    └─ Phase 1: Has identity registered?
 *    └─ Phase 2: Has valid claims (KYC, accreditation)?
 * 
 * 5. CHECK: Transfer passes compliance
 *    └─ compliance.canTransfer(sender, receiver, amount)
 *    └─ Iterates through all compliance modules
 *    └─ All modules must return true
 * 
 * 6. EXECUTE: Transfer tokens
 *    └─ _transfer(sender, receiver, amount)
 *    └─ Update balances in ERC20
 * 
 * 7. NOTIFY: Update compliance state
 *    └─ compliance.transferred(sender, receiver, amount)
 *    └─ Modules update their state (balances, counters, etc.)
 * 
 * ============================================================================
 * KEY FEATURES
 * ============================================================================
 * 
 * 1. PERMISSIONED TRANSFERS
 *    - Only verified investors can receive tokens
 *    - All transfers must pass compliance checks
 *    - Frozen addresses cannot send or receive
 * 
 * 2. AGENT CONTROLS
 *    - Mint: Create new tokens for verified investors
 *    - Burn: Destroy tokens from any address
 *    - Freeze: Block specific addresses or token amounts
 *    - Forced Transfer: Move tokens without compliance (court orders)
 * 
 * 3. PARTIAL FREEZING
 *    - Freeze specific token amounts, not entire balance
 *    - Investor can still trade unfrozen tokens
 *    - Used for vesting, lockups, legal holds
 * 
 * 4. REDEMPTION
 *    - Investors can request redemption for underlying asset
 *    - Burns tokens and emits event
 *    - Off-chain processing (Phase 5: RedemptionManager)
 * 
 * 5. BATCH OPERATIONS
 *    - Mint/burn/transfer to multiple addresses
 *    - Gas-efficient for airdrops, distributions
 * 
 * ============================================================================
 * SECURITY MODEL
 * ============================================================================
 * 
 * ROLES:
 * 
 * 1. Owner (DEFAULT_ADMIN_ROLE)
 *    - Set identity registry
 *    - Set compliance contract
 *    - Grant/revoke agent roles
 *    - Cannot mint/burn/transfer directly
 * 
 * 2. Agents (AGENT_ROLE)
 *    - Mint tokens to verified investors
 *    - Burn tokens from any address
 *    - Freeze/unfreeze addresses
 *    - Forced transfers (regulatory actions)
 *    - Pause/unpause token
 *    - Cannot change identity registry or compliance
 * 
 * 3. Investors (no role)
 *    - Transfer tokens (if verified and compliant)
 *    - Request redemption
 *    - Cannot mint, burn, or freeze
 * 
 * ACCESS CONTROL MATRIX:
 * 
 * Function              | Owner | Agent | Investor
 * ----------------------|-------|-------|----------
 * transfer()            |   ✓   |   ✓   |    ✓
 * mint()                |   ✗   |   ✓   |    ✗
 * burn()                |   ✗   |   ✓   |    ✗
 * freeze()              |   ✗   |   ✓   |    ✗
 * forcedTransfer()      |   ✗   |   ✓   |    ✗
 * pause()               |   ✗   |   ✓   |    ✗
 * requestRedemption()   |   ✓   |   ✓   |    ✓
 * setIdentityRegistry() |   ✓   |   ✗   |    ✗
 * setCompliance()       |   ✓   |   ✗   |    ✗
 * 
 * ============================================================================
 * FREEZING MECHANICS
 * ============================================================================
 * 
 * Two types of freezing:
 * 
 * 1. FULL ADDRESS FREEZE
 *    - setAddressFrozen(address, true)
 *    - Address cannot send OR receive tokens
 *    - Used for: Sanctions, legal holds, suspicious activity
 * 
 * 2. PARTIAL TOKEN FREEZE
 *    - freezePartialTokens(address, amount)
 *    - Specific tokens cannot be transferred
 *    - Investor can still trade unfrozen tokens
 *    - Used for: Vesting schedules, lockup periods
 * 
 * Example:
 * 
 * Investor has 1000 tokens
 * Agent freezes 600 tokens
 * 
 * Available balance: 1000 - 600 = 400 tokens
 * Can transfer: Up to 400 tokens
 * Cannot transfer: More than 400 tokens
 * 
 * Forced transfers and burns can move frozen tokens:
 * - forcedTransfer(): Unfreezes as needed
 * - burn(): Unfreezes as needed
 * 
 * ============================================================================
 * COMPLIANCE INTEGRATION
 * ============================================================================
 * 
 * StockToken delegates compliance checks to ModularCompliance:
 * 
 * Before transfer:
 * ```solidity
 * require(
 *     _compliance.canTransfer(from, to, amount),
 *     "StockToken: transfer not compliant"
 * );
 * ```
 * 
 * After transfer:
 * ```solidity
 * _compliance.transferred(from, to, amount);
 * ```
 * 
 * This allows:
 * - Adding/removing compliance rules without redeploying token
 * - Different rules for different tokens (same registry)
 * - Compliance state tracking (balances, counters, etc.)
 * 
 * Example compliance modules:
 * - MaxBalanceModule: Limit tokens per identity
 * - TransferLimitModule: Daily transfer limits
 * - AccreditedInvestorModule: Only accredited investors
 * - CountryRestrictionModule: Block sanctioned countries
 * 
 * ============================================================================
 * REDEMPTION FLOW
 * ============================================================================
 * 
 * Phase 3 (Current): Basic redemption
 * 
 * 1. Investor calls: token.requestRedemption(amount)
 * 2. Token burns tokens
 * 3. Token emits: RedemptionRequested(investor, amount)
 * 4. Off-chain: Process stock sale
 * 5. Off-chain: Send USDC to investor
 * 
 * Phase 5 (Future): Integrated redemption
 * 
 * 1. Investor calls: token.requestRedemption(amount)
 * 2. Token burns tokens
 * 3. Token calls: redemptionManager.requestRedemption(investor, amount)
 * 4. RedemptionManager triggers: Chainlink Functions → Sell stock
 * 5. Callback: redemptionManager.fulfillRedemption(requestId, usdcAmount)
 * 6. Investor calls: redemptionManager.withdraw()
 * 7. Investor receives: USDC
 * 
 * ============================================================================
 * COMPARISON: ERC-3643 vs rwa-creator vs Our Implementation
 * ============================================================================
 * 
 * Feature                  | ERC-3643  | rwa-creator | StockToken
 * -------------------------|-----------|-------------|------------
 * Identity verification    |     ✓     |      ✗      |     ✓
 * Compliance modules       |     ✓     |      ✗      |     ✓
 * Freezing                 |     ✓     |      ✗      |     ✓
 * Forced transfers         |     ✓     |      ✗      |     ✓
 * Oracle integration       |     ✗     |      ✓      |  Phase 4
 * Redemption               |     ✗     |      ✓      |     ✓
 * Collateral verification  |     ✗     |      ✓      |  Phase 4
 * 
 * Our implementation combines the best of both:
 * - ERC-3643: Identity + compliance framework
 * - rwa-creator: Redemption + oracle integration (Phase 4-5)
 * 
 * ============================================================================
 * DESIGN DECISIONS
 * ============================================================================
 * 
 * 1. WHY PAUSE ON DEPLOYMENT?
 *    - Safety: Prevents transfers before setup complete
 *    - Agent must explicitly unpause after configuration
 *    - Prevents accidental minting/transfers during testing
 * 
 * 2. WHY SEPARATE IDENTITY AND COMPLIANCE?
 *    - Identity: "Who can hold tokens?" (persistent)
 *    - Compliance: "What rules apply?" (changeable)
 *    - Different upgrade cycles
 *    - Different audit scopes
 * 
 * 3. WHY ALLOW FORCED TRANSFERS?
 *    - Court orders (legal requirement)
 *    - Wallet recovery (investor loses keys)
 *    - Regulatory actions (sanctions)
 *    - Still requires receiver to be verified
 * 
 * 4. WHY BURN ON REDEMPTION?
 *    - Prevents double-spending (token + stock)
 *    - Maintains 1:1 backing ratio
 *    - Follows rwa-creator pattern
 * 
 * 5. WHY NOTIFY COMPLIANCE AFTER TRANSFER?
 *    - Compliance modules track state (balances, counters)
 *    - Must update after successful transfer
 *    - If module reverts, entire transaction reverts
 * 
 * ============================================================================
 * GAS OPTIMIZATION
 * ============================================================================
 * 
 * 1. Immutable decimals
 *    - Set once in constructor
 *    - Saves SLOAD on every decimals() call
 * 
 * 2. Batch operations
 *    - Mint/burn/transfer multiple addresses in one transaction
 *    - Amortize base transaction cost
 * 
 * 3. View functions for checks
 *    - canTransfer() is view (no gas for checks)
 *    - Only pay gas if transfer executes
 * 
 * 4. Early reverts
 *    - Check paused/frozen first (cheapest checks)
 *    - Identity/compliance checks later (more expensive)
 * 
 * ============================================================================
 * TESTING STRATEGY
 * ============================================================================
 * 
 * Unit Tests (StockTokenTest.t.sol):
 * - Deployment
 * - Mint/burn (agent only)
 * - Transfer (with all checks)
 * - Freezing (full and partial)
 * - Forced transfers
 * - Redemption
 * - Pause/unpause
 * - Admin functions
 * - Integration with compliance
 * 
 * Edge Cases:
 * - Transfer frozen tokens → revert
 * - Mint to unverified → revert
 * - Transfer when paused → revert
 * - Burn more than balance → revert
 * - Freeze more than balance → revert
 * - Forced transfer unfreezes as needed
 * 
 * Integration Tests:
 * - Complete lifecycle (mint → transfer → redeem)
 * - Multiple investors with compliance
 * - Compliance module interactions
 * 
 * ============================================================================
 * FUTURE ENHANCEMENTS (Phase 4-5)
 * ============================================================================
 * 
 * Phase 4: Oracle Integration
 * - OracleManager contract
 * - Chainlink Functions for custody verification
 * - Collateralization checks before minting
 * - Portfolio balance tracking
 * 
 * Phase 5: Redemption Manager
 * - RedemptionManager contract
 * - Async settlement (burn → sell → withdraw)
 * - Withdrawal queue
 * - Minimum redemption amounts
 * 
 * Additional Features:
 * - Dividend distribution
 * - Voting rights (governance)
 * - Transfer restrictions (lockup periods)
 * - Whitelist/blacklist
 * - Recovery mechanisms
 * 
 * ============================================================================
 * DEPLOYMENT CHECKLIST
 * ============================================================================
 * 
 * 1. Deploy IdentityRegistry
 * 2. Deploy ModularCompliance
 * 3. Deploy compliance modules (MaxBalance, TransferLimit, etc.)
 * 4. Add modules to compliance
 * 5. Deploy StockToken (with registry + compliance addresses)
 * 6. Grant agent roles
 * 7. Register investor identities
 * 8. Unpause token
 * 9. Mint initial supply
 * 10. Test transfers
 * 
 * ============================================================================
 * SECURITY CONSIDERATIONS
 * ============================================================================
 * 
 * 1. Agent Key Management
 *    - Use multi-sig for agent role
 *    - Rotate keys regularly
 *    - Monitor agent actions
 * 
 * 2. Compliance Updates
 *    - Test new modules thoroughly
 *    - Gradual rollout (add one module at a time)
 *    - Monitor gas costs
 * 
 * 3. Identity Registry
 *    - Verify KYC provider trustworthiness
 *    - Regular audits of registered identities
 *    - Remove invalid identities promptly
 * 
 * 4. Pause Mechanism
 *    - Use only for emergencies
 *    - Communicate with investors
 *    - Have clear unpause criteria
 * 
 * 5. Forced Transfers
 *    - Require legal documentation
 *    - Log all forced transfers
 *    - Notify affected investors
 * 
 * ============================================================================
 * REGULATORY COMPLIANCE
 * ============================================================================
 * 
 * This token is designed for:
 * - Reg D private placements (US)
 * - Reg S international offerings
 * - Reg A+ mini-IPOs
 * 
 * Key features for compliance:
 * - KYC/AML via identity registry
 * - Accredited investor verification
 * - Transfer restrictions (lockup periods)
 * - Investor limits (Rule 506)
 * - Audit trail (all events logged)
 * 
 * Consult legal counsel before deployment.
 * 
 * ============================================================================
 */
