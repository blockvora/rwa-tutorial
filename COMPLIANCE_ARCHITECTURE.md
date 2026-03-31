# Compliance Architecture: Modular Rule Engine

## Overview

The compliance system is a **pluggable rule engine** that enforces regulatory requirements on token transfers. It's completely separate from the token contract, allowing rules to evolve without redeploying the token.

## Why Separate from Token?

### 1. **Separation of Concerns**

```
Token Contract:          Compliance Contract:
- ERC20 mechanics        - Regulatory rules
- Balance tracking       - Business logic
- Transfer execution     - Rule orchestration
- Identity checks        - Audit trail
```

**Benefits:**
- Token focuses on "CAN transfer happen?" (technical)
- Compliance focuses on "SHOULD transfer happen?" (legal)
- Each can be audited independently
- Easier to test and maintain

### 2. **Upgradeability**

```solidity
// Regulations change → swap compliance, keep token
token.setCompliance(address(newCompliance));

// Token address unchanged
// No investor re-registration
// No token migration
```

### 3. **Modularity**

```solidity
// Different tokens, different rules
stockA.setCompliance(usAccreditedCompliance);
stockB.setCompliance(globalRetailCompliance);

// Same token, evolving rules
compliance.addModule(newTransferLimitModule);
compliance.removeModule(oldCountryModule);
```

### 4. **Gas Efficiency**

- Token transfers are frequent → must be fast
- Compliance checks can be complex → can be slower
- Separation allows optimization of each

### 5. **Testing & Auditing**

- Test token logic independently
- Test compliance logic independently
- Test modules independently
- Smaller audit scope = higher quality

---

## Architecture

### **Component Hierarchy**

```
┌─────────────────────────────────────────────────────────────┐
│                    StockToken.sol                           │
│  - transfer() calls compliance.canTransfer()                │
│  - After transfer, calls compliance.transferred()           │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                 ModularCompliance.sol                       │
│  - Orchestrates multiple modules                            │
│  - Iterates through all modules for checks                  │
│  - Notifies modules of state changes                        │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│              ComplianceModules (pluggable)                  │
│  ├─ AccreditedInvestorModule (stateless)                   │
│  ├─ MaxBalanceModule (identity-based state)                │
│  ├─ TransferLimitModule (time-based state)                 │
│  └─ [Future modules...]                                     │
└─────────────────────────────────────────────────────────────┘
```

---

## Core Contracts

### **1. ModularCompliance.sol** (Orchestrator)

**Responsibility:** Coordinate multiple compliance modules

**Key Functions:**
```solidity
// Check if transfer is compliant (view)
function canTransfer(address from, address to, uint256 amount) 
    external view returns (bool);

// Notify modules after transfer (state update)
function transferred(address from, address to, uint256 amount) 
    external;

// Module management
function addModule(address module) external onlyOwner;
function removeModule(address module) external onlyOwner;
```

**How it works:**
1. Token calls `canTransfer(from, to, amount)`
2. Compliance iterates through all modules
3. Each module's `moduleCheck()` must return true
4. If ANY module rejects, return false
5. If all pass, return true to token
6. Token executes transfer
7. Token calls `transferred(from, to, amount)`
8. Compliance notifies all modules to update state

**Security:**
- Only bound token can call state update functions
- Only owner can add/remove modules
- Limited to 25 modules (prevent gas DoS)

---

### **2. AbstractModule.sol** (Base Class)

**Responsibility:** Common functionality for all modules

**Provides:**
- Compliance binding management
- Identity registry integration
- Helper functions (`_getIdentity`, `_isVerified`, `_getCountry`)
- Access control for module functions

**Usage:**
```solidity
contract MyModule is AbstractModule {
    constructor(address identityRegistry) 
        AbstractModule(identityRegistry) {}
    
    function moduleCheck(...) external view override returns (bool) {
        // Your compliance logic here
    }
    
    function name() external pure override returns (string memory) {
        return "MyModule";
    }
}
```

---

### **3. AccreditedInvestorModule.sol** (Stateless)

**Pattern:** Claim-based verification

**Rule:** Only accredited investors can receive tokens

**Implementation:**
```solidity
function moduleCheck(address from, address to, uint256 amount, address compliance)
    external view override returns (bool)
{
    // Check if receiver is verified (includes accreditation in Phase 2)
    return _isVerified(to);
}

function moduleTransferAction(...) external override {
    // No-op: Stateless module
}
```

**Why stateless:**
- Accreditation status stored in identity contracts
- No need to track state in module
- Gas-efficient (no storage writes)

**Use case:** Reg D securities, private placements

---

### **4. MaxBalanceModule.sol** (Identity-Based State)

**Pattern:** Identity-based accounting

**Rule:** No identity can hold more than maxBalance tokens

**Implementation:**
```solidity
mapping(address => uint256) public identityBalance; // identity => balance

function moduleCheck(address from, address to, uint256 amount, address compliance)
    external view override returns (bool)
{
    address toIdentity = _getIdentity(to);
    
    // Check if receiver would exceed max
    return (identityBalance[toIdentity] + amount) <= maxBalance;
}

function moduleTransferAction(address from, address to, uint256 amount)
    external override onlyBoundCompliance
{
    address fromIdentity = _getIdentity(from);
    address toIdentity = _getIdentity(to);
    
    // Update balances per IDENTITY (not per wallet)
    identityBalance[fromIdentity] -= amount;
    identityBalance[toIdentity] += amount;
}
```

**Why per identity:**
- One person can have multiple wallets
- Compliance rules apply to the person, not the wallet
- Prevents circumventing limits by using multiple addresses

**Use case:** Prevent concentration of ownership, shareholder limits

---

### **5. TransferLimitModule.sol** (Time-Based State)

**Pattern:** Time-windowed accounting

**Rule:** No identity can transfer more than dailyLimit per day

**Implementation:**
```solidity
// identity => day => volume
mapping(address => mapping(uint256 => uint256)) public dailyTransferVolume;

function moduleCheck(address from, address to, uint256 amount, address compliance)
    external view override returns (bool)
{
    address fromIdentity = _getIdentity(from);
    uint256 today = block.timestamp / 1 days;
    uint256 currentVolume = dailyTransferVolume[fromIdentity][today];
    
    return (currentVolume + amount) <= dailyLimit;
}

function moduleTransferAction(address from, address to, uint256 amount)
    external override onlyBoundCompliance
{
    address fromIdentity = _getIdentity(from);
    uint256 today = block.timestamp / 1 days;
    
    // Increment daily counter (auto-resets when day changes)
    dailyTransferVolume[fromIdentity][today] += amount;
}
```

**Why time-based:**
- Prevent rapid liquidation (market manipulation)
- Comply with Reg D restrictions (limited resale)
- Detect suspicious activity

**Use case:** Reg D Rule 144, anti-manipulation, AML compliance

---

## Data Flow

### **Transfer Flow (with Compliance)**

```
1. User calls: token.transfer(to, 100)
    ↓
2. Token checks: identityRegistry.isVerified(to)? ✓
    ↓
3. Token checks: compliance.canTransfer(from, to, 100)?
    ↓
4. Compliance iterates modules:
    ├─ AccreditedInvestorModule.moduleCheck() → true
    ├─ MaxBalanceModule.moduleCheck() → true
    └─ TransferLimitModule.moduleCheck() → true
    ↓
5. All pass → return true
    ↓
6. Token executes: _transfer(from, to, 100)
    ↓
7. Token notifies: compliance.transferred(from, to, 100)
    ↓
8. Compliance iterates modules:
    ├─ AccreditedInvestorModule.moduleTransferAction() → no-op
    ├─ MaxBalanceModule.moduleTransferAction() → update balances
    └─ TransferLimitModule.moduleTransferAction() → increment counter
    ↓
9. Transfer complete
```

### **Module Lifecycle**

```
1. Deploy module
   ↓
2. Owner calls: compliance.addModule(moduleAddress)
   ↓
3. Compliance calls: module.bindCompliance(complianceAddress)
   ↓
4. Module is now active
   ↓
5. Every transfer calls: module.moduleCheck()
   ↓
6. After transfer: module.moduleTransferAction()
   ↓
7. Owner calls: compliance.removeModule(moduleAddress)
   ↓
8. Compliance calls: module.unbindCompliance(complianceAddress)
   ↓
9. Module is now inactive
```

---

## Module Patterns

### **Pattern 1: Stateless Module**

**Example:** AccreditedInvestorModule, CountryRestrictionModule

**Characteristics:**
- No state to update
- Just checks external data (identity registry, claims)
- `moduleTransferAction()` is no-op
- Gas-efficient

**When to use:**
- Rule depends only on identity/claims
- No need to track counters or balances

### **Pattern 2: Stateful Module (Identity-Based)**

**Example:** MaxBalanceModule

**Characteristics:**
- Tracks state per IDENTITY (not per wallet)
- Updates state on transfer/mint/burn
- Prevents multi-wallet circumvention

**When to use:**
- Rule applies to the person, not the wallet
- Need to track balances or ownership

### **Pattern 3: Stateful Module (Time-Based)**

**Example:** TransferLimitModule

**Characteristics:**
- Tracks state per time window (day, month, etc.)
- Auto-resets when window changes
- Uses `block.timestamp` for calculations

**When to use:**
- Rate limiting (daily/monthly transfer limits)
- Time-locked transfers (vesting, lockup periods)

---

## Extension Points

### **Future Modules**

1. **CountryRestrictionModule**
   - Block transfers to sanctioned countries
   - Check: `!isCountryBlocked(_getCountry(to))`

2. **TimeLockedTransferModule**
   - Lock tokens for vesting periods
   - Check: `block.timestamp >= unlockTime[from]`

3. **WhitelistModule**
   - Only allow transfers to pre-approved addresses
   - Check: `isWhitelisted[to]`

4. **TradingHoursModule**
   - Only allow transfers during market hours
   - Check: `isMarketOpen(block.timestamp)`

5. **ConcentrationLimitModule**
   - Prevent single identity from owning >X% of supply
   - Check: `(balance[identity] + amount) / totalSupply <= MAX_CONCENTRATION`

6. **LockupPeriodModule**
   - Reg D: No transfers for 12 months after issuance
   - Check: `block.timestamp >= issueDate + 365 days`

### **Module Composition**

```solidity
// Combine modules for complex rules
compliance.addModule(accreditedInvestorModule);  // Must be accredited
compliance.addModule(maxBalanceModule);          // Max 1M tokens per identity
compliance.addModule(transferLimitModule);       // Max 100K per day
compliance.addModule(countryRestrictionModule);  // No sanctioned countries

// All must pass for transfer to succeed
// Any can be removed if regulations change
```

---

## Security Considerations

### **1. Module Authorization**

**Problem:** Malicious module could brick transfers

**Solution:** Only compliance can call module functions

```solidity
modifier onlyBoundCompliance() {
    require(_boundCompliances[msg.sender], "Not bound");
    _;
}
```

### **2. Module Limit**

**Problem:** Too many modules = gas DoS

**Solution:** Cap at 25 modules

```solidity
uint256 public constant MAX_MODULES = 25;
```

### **3. Atomic State Updates**

**Problem:** Transfer succeeds but state update fails

**Solution:** Module reverts = entire transaction reverts

```solidity
function transferred(...) external onlyToken {
    for (uint i = 0; i < modules.length; i++) {
        modules[i].moduleTransferAction(...); // Reverts if fails
    }
}
```

### **4. Reentrancy Protection**

**Problem:** Module could call back into token

**Solution:** Use view functions for checks

```solidity
function canTransfer(...) external view returns (bool) {
    // View function = no state changes = no reentrancy
}
```

---

## Testing Strategy

### **Unit Tests**

1. **ModularCompliance Tests**
   - Token binding
   - Module management (add/remove)
   - canTransfer() logic
   - State update notifications

2. **Module Tests**
   - Compliance binding
   - moduleCheck() logic
   - State updates (transfer/mint/burn)
   - Edge cases

### **Integration Tests**

1. **Complete Transfer Flow**
   - Setup: Bind token, add modules
   - Mint to investor
   - Check canTransfer()
   - Execute transfer
   - Verify state updated

2. **Multi-Module Scenarios**
   - All modules pass
   - One module rejects
   - Multiple transfers (daily limits)
   - Time-based resets

---

## Implementation Status

### ✅ **Phase 2: Compliance (COMPLETE)**

**Contracts:**
- ✅ `ModularCompliance.sol` - Orchestrator
- ✅ `AbstractModule.sol` - Base class
- ✅ `AccreditedInvestorModule.sol` - Stateless example
- ✅ `MaxBalanceModule.sol` - Identity-based example
- ✅ `TransferLimitModule.sol` - Time-based example

**Tests:**
- ✅ `ModularComplianceTest.t.sol` - 30+ tests
- ✅ `ComplianceModulesTest.t.sol` - 50+ tests

**Features:**
- ✅ Pluggable module system
- ✅ Three module patterns demonstrated
- ✅ Comprehensive test coverage
- ✅ Security controls (access, limits)

---

## Next Steps

### 🚧 **Phase 3: Stock Token**

Implement the main token contract:
- ERC-3643 Token base
- Identity verification on transfers
- Compliance checks on transfers
- Agent-controlled minting
- Integration with IdentityRegistry + ModularCompliance

**Key Integration:**
```solidity
function transfer(address to, uint256 amount) external returns (bool) {
    require(_identityRegistry.isVerified(to), "Not verified");
    require(_compliance.canTransfer(msg.sender, to, amount), "Not compliant");
    
    _transfer(msg.sender, to, amount);
    
    _compliance.transferred(msg.sender, to, amount);
    return true;
}
```

---

## Resources

- **ERC-3643 Standard:** https://eips.ethereum.org/EIPS/eip-3643
- **T-REX Whitepaper:** https://tokeny.com/erc3643-whitepaper/
- **Reference Implementation:** `reference/erc3643/`

---

**Built with:** Solidity 0.8.25, Foundry, OpenZeppelin
