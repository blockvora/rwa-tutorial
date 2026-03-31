# Tokenized Stock Tutorial (ERC-3643 + RWA)

A developer-grade tutorial for building permissioned security tokens that combine:
- **ERC-3643 identity and compliance** (from T-REX standard)
- **RWA lifecycle management** (from rwa-creator: mint → redeem → async settlement)
- **Oracle integration** (Chainlink Functions for custody verification)

## Architecture Overview

This tutorial implements a **minimal but production-ready** architecture for tokenizing real-world assets (specifically stocks) with regulatory compliance.

### Core Components

```
StockToken (ERC-3643 Token)
├── IdentityRegistry (who can hold tokens?)
│   ├── Wallet → Identity mapping
│   └── Claim verification (KYC, accreditation)
├── ModularCompliance (what rules apply?)
│   ├── AccreditedInvestorModule
│   ├── MaxBalanceModule
│   └── CountryRestrictionModule
├── OracleManager (is backing valid?)
│   └── Chainlink Functions → Brokerage API
└── RedemptionManager (how to exit?)
    └── Async settlement: burn → sell stock → withdraw USDC
```

## Current Implementation Status

### ✅ Phase 1: Identity Registry (COMPLETE)

The `IdentityRegistry` contract is fully implemented and tested:

**Features:**
- Agent-managed identity registration
- Wallet → ONCHAINID mapping
- Country code tracking (for compliance)
- Extensible for claim verification (Phase 2)

**Files:**
```
src/identity/
├── IdentityRegistry.sol           # Main registry contract
├── interfaces/
│   ├── IIdentityRegistry.sol      # Registry interface
│   ├── IIdentity.sol              # ONCHAINID interface
│   ├── IClaimTopicsRegistry.sol   # Required claims (Phase 2)
│   ├── ITrustedIssuersRegistry.sol # Trusted KYC providers (Phase 2)
│   └── IClaimIssuer.sol           # Claim issuer interface (Phase 2)
└── mocks/
    └── MockIdentity.sol           # Test identity contract
```

**Tests:**
```
test/unit/IdentityRegistryTest.t.sol
├── ✅ Registration (agent-only)
├── ✅ Update identity (switch KYC provider)
├── ✅ Update country (investor relocates)
├── ✅ Delete identity (lose eligibility)
├── ✅ Verification (Phase 1: simple check)
├── ✅ Role management (admin/agent)
└── ✅ Integration tests (full lifecycle)
```

**Run tests:**
```bash
forge test --match-contract IdentityRegistryTest -vv
```

### ✅ Phase 2: Compliance Modules (COMPLETE)

The modular compliance system is fully implemented and tested:

**Features:**
- Pluggable module architecture
- Three module patterns (stateless, identity-based, time-based)
- Module orchestration via ModularCompliance
- Comprehensive access control

**Files:**
```
src/compliance/
├── ModularCompliance.sol              # Orchestrator contract
├── interfaces/
│   ├── IModularCompliance.sol         # Compliance interface
│   └── IModule.sol                    # Module interface
└── modules/
    ├── AbstractModule.sol             # Base class for modules
    ├── AccreditedInvestorModule.sol   # Stateless module (claim-based)
    ├── MaxBalanceModule.sol           # Identity-based state tracking
    └── TransferLimitModule.sol        # Time-based rate limiting
```

**Tests:**
```
test/unit/
├── ModularComplianceTest.t.sol        # 30+ tests for orchestrator
└── ComplianceModulesTest.t.sol        # 50+ tests for modules
```

**Run tests:**
```bash
forge test --match-contract ModularComplianceTest -vv
forge test --match-contract ComplianceModulesTest -vv
```

**Documentation:**
See [COMPLIANCE_ARCHITECTURE.md](./COMPLIANCE_ARCHITECTURE.md) for detailed explanation of:
- Why compliance is separate from token
- Module patterns and examples
- Data flow and lifecycle
- Extension points for custom modules

### 🚧 Phase 3: Stock Token (TODO)

Implement the main token contract:
- ERC-3643 Token base
- Identity verification on transfers
- Compliance checks on transfers
- Agent-controlled minting
- Integration with OracleManager

### 🚧 Phase 4: Oracle Integration (TODO)

Implement Chainlink Functions integration:
- `OracleManager.sol` (custody verification)
- Collateralization checks before minting
- Portfolio balance tracking

### 🚧 Phase 5: Redemption (TODO)

Implement async redemption:
- `RedemptionManager.sol`
- Burn tokens → sell stocks → withdraw USDC
- Withdrawal queue management

## Key Design Decisions

### 1. **Simplified vs. Full ERC-3643**

| Feature | Full ERC-3643 | Our Implementation |
|---------|---------------|-------------------|
| Storage separation | ✅ Separate contract | ❌ Embedded (tutorial) |
| Batch operations | ✅ Yes | ❌ No (clearer) |
| Upgradeability | ✅ Proxy pattern | ❌ Direct (simpler) |
| Claim verification | ✅ Required | 🔶 Optional (extensible) |

**Why:** Tutorial focuses on core concepts without overwhelming complexity.

### 2. **Two-Phase Verification**

**Phase 1 (Current):**
```solidity
isVerified(wallet) → has identity? → true/false
```

**Phase 2 (Future):**
```solidity
isVerified(wallet) → has identity? → has valid claims? → true/false
```

**Why:** Progressive learning. Start simple, add complexity.

### 3. **Agent Role Pattern**

- **Agents** = KYC providers, compliance officers
- **Admin** = Token owner, can manage agents
- **Investors** = Can only transfer (if verified)

**Why:** Matches real-world regulatory structure.

## Tutorial Progression

### Step 1: Identity Basics ✅
- Deploy `IdentityRegistry`
- Register mock identities
- Test verification (simple)
- **Learning:** Wallet → identity mapping

### Step 2: Compliance Rules ✅
- Deploy `ModularCompliance`
- Create compliance modules
- Test transfer restrictions
- **Learning:** Modular rule enforcement

### Step 3: Claims (Next)
- Deploy `ClaimTopicsRegistry`
- Deploy `TrustedIssuersRegistry`
- Add claims to identities
- Test verification (complex)
- **Learning:** Claim-based verification

### Step 5: Token Integration
- Deploy `StockToken`
- Connect identity + compliance
- Test permissioned transfers
- **Learning:** ERC-3643 token flow

### Step 6: Oracle Backing
- Deploy `OracleManager`
- Mock Chainlink Functions
- Test collateralized minting
- **Learning:** Off-chain asset verification

### Step 6: Redemption
- Deploy `RedemptionManager`
- Test async settlement
- **Learning:** RWA lifecycle management

## Reference Repositories

This tutorial is based on two production-grade codebases:

### 1. **ERC-3643** (T-REX Standard)
- **Source:** `reference/erc3643/`
- **What we use:** Identity registry, compliance modules, agent roles
- **What we simplify:** Storage separation, batch operations, upgradeability

### 2. **rwa-creator** (Patrick Collins)
- **Source:** `reference/rwa-creator/`
- **What we use:** Oracle integration (dTSLA), redemption flow, collateralization
- **What we add:** Identity layer, compliance enforcement

## Getting Started

### Prerequisites
```bash
# Install Foundry
curl -L https://foundry.paradigm.xyz | bash
foundryup

# Clone repository
git clone <your-repo>
cd rwa-tutorial
```

### Installation

**Quick Start:**
```bash
# 1. Initialize git (required for forge install)
git init
git add .
git commit -m "Initial commit"

# 2. Install dependencies
forge install OpenZeppelin/openzeppelin-contracts@v5.0.0
forge install foundry-rs/forge-std

# 3. Build contracts
forge build

# 4. Run tests
forge test -vv
```

**Or use the installation script:**
```bash
chmod +x install-deps.sh
./install-deps.sh
```

**Troubleshooting:**
If you get "Source not found" errors, see [TROUBLESHOOTING.md](./TROUBLESHOOTING.md)

### Project Structure
```
rwa-tutorial/
├── src/
│   ├── identity/           # ✅ Phase 1 (complete)
│   ├── compliance/         # ✅ Phase 2 (complete)
│   ├── token/              # ✅ Phase 3 (complete)
│   ├── oracle/             # 🚧 Phase 4 (todo)
│   └── redemption/         # 🚧 Phase 5 (todo)
├── test/
│   └── unit/
│       ├── IdentityRegistryTest.t.sol      # ✅ Complete
│       ├── ModularComplianceTest.t.sol     # ✅ Complete
│       ├── ComplianceModulesTest.t.sol     # ✅ Complete
│       └── StockTokenTest.t.sol            # ✅ Complete
├── reference/
│   ├── erc3643/            # Reference implementation
│   └── rwa-creator/        # Reference implementation
└── README.md               # This file
```

## Key Concepts Explained

### What is ONCHAINID?
- A smart contract representing an investor's identity
- Stores **claims** (KYC, accreditation, country)
- Claims are signed by **trusted issuers** (KYC providers)
- Persistent across multiple tokens

### What are Claims?
- Attestations about an investor (e.g., "is accredited")
- Signed by trusted issuers
- Have topics (1 = KYC, 2 = Accreditation, etc.)
- Can be verified on-chain

### What is Modular Compliance?
- Pluggable rule system for token transfers
- Each module checks one rule (max balance, country, etc.)
- Token owner can add/remove modules
- All modules must pass for transfer to succeed

### What is the RWA Lifecycle?
1. **Mint:** Agent verifies off-chain backing → mints tokens
2. **Transfer:** Investors trade (if compliant)
3. **Redeem:** Investor burns tokens → triggers stock sale
4. **Settle:** Stock sold → USDC sent → investor withdraws

## Security Considerations

### Trust Assumptions
1. **Off-chain custodian** (brokerage) holds real stocks
2. **Chainlink DON** accurately reports custody data
3. **KYC issuers** properly verify investor eligibility
4. **Agents** act in good faith (don't mint without backing)
5. **Token owner** sets appropriate compliance rules

### Access Control
- **Admin:** Can manage agents, set registries
- **Agents:** Can register/update/delete identities
- **Investors:** Can only transfer (if verified)

### Audit Recommendations
Before production:
1. Full security audit of all contracts
2. Chainlink Functions script review
3. Brokerage integration testing
4. Compliance rule validation
5. Agent key management review

## License

MIT (for tutorial code)

Note: ERC-3643 reference code is GPL-3.0 (see `reference/erc3643/LICENSE.md`)

## Contributing

This is a tutorial repository. Contributions welcome:
- Bug fixes
- Test improvements
- Documentation clarifications
- Additional compliance modules

## Disclaimer

**This code is for educational purposes only.**

- Not audited
- Not production-ready without modifications
- Regulatory compliance is complex and jurisdiction-specific
- Consult legal counsel before tokenizing securities

## Next Steps

1. ✅ Complete Phase 1 (Identity Registry)
2. ✅ Complete Phase 2 (Compliance Modules)
3. ✅ Complete Phase 3 (Stock Token)
4. 🚧 Implement Phase 4 (Oracle Integration)
5. 🚧 Implement Phase 5 (Redemption Manager)
6. 🚧 Write integration tests
7. 🚧 Deploy to testnet
8. 🚧 Create deployment scripts

## Resources

- [ERC-3643 Standard](https://eips.ethereum.org/EIPS/eip-3643)
- [T-REX Whitepaper](https://tokeny.com/erc3643-whitepaper/)
- [ONCHAINID Documentation](https://docs.onchainid.com/)
- [Chainlink Functions](https://docs.chain.link/chainlink-functions)
- [rwa-creator Repository](https://github.com/PatrickAlphaC/rwa-creator)

---

**Built with:** Solidity 0.8.25, Foundry, OpenZeppelin

**Tutorial by:** [Your Name]
