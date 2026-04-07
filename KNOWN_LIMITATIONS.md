# Known Limitations & Production Gaps

**Last Updated:** April 1, 2026  
**Status:** Tutorial Implementation

---

## Overview

This codebase demonstrates **RWA tokenization architecture** with intentional simplifications for educational purposes. It is NOT production-ready and should NOT be deployed with real assets without significant enhancements.

---

## What's Missing (By Design)

### 🔴 Critical for Production

#### 1. Multi-Signature Governance
**Current:** Single admin/agent keys  
**Required:** 3-of-5 Gnosis Safe for all privileged operations  
**Risk:** Single key compromise = total loss

#### 2. Collateral Ratio Enforcement
**Current:** Optional oracle check (disabled by default)  
**Required:** Mandatory on-chain verification before every mint  
**Risk:** Unbacked token issuance

#### 3. Circuit Breakers
**Current:** None  
**Required:** Auto-pause on price anomalies, high redemption volume  
**Risk:** Bank run, market manipulation

#### 4. Rate Limiting
**Current:** None  
**Required:** Daily/weekly caps on minting and redemption  
**Risk:** Flash attacks, economic exploitation

#### 5. Upgradeability
**Current:** Immutable contracts  
**Required:** UUPS proxy with timelock  
**Risk:** Cannot fix bugs or add features

---

### 🟡 Important for Production

#### 6. Real KYC/AML Integration
**Current:** Simplified identity verification (Phase 1)  
**Required:** Licensed provider (Chainalysis, Sumsub), sanctions screening  
**Risk:** Regulatory non-compliance

#### 7. Custody Integration
**Current:** Mock oracles  
**Required:** Qualified custodian (Fireblocks, Coinbase Custody)  
**Risk:** No proof of reserves

#### 8. Brokerage API Integration
**Current:** Manual oracle finalization  
**Required:** Automated settlement via Alpaca/Interactive Brokers  
**Risk:** Operational overhead, human error

#### 9. Oracle Committee
**Current:** Single oracle role  
**Required:** 3-of-5 multi-sig oracle committee  
**Risk:** Front-running, price manipulation

#### 10. Economic Safeguards
**Current:** Basic slippage protection only  
**Required:** Reserve fund, insurance fund, liquidation mechanism  
**Risk:** Undercollateralization, insolvency

---

## Security Fixes Applied

### ✅ Fixed: Redemption Manager Balance Check
**Issue:** Contract could finalize redemptions without sufficient USDC  
**Fix:** Added balance verification before crediting withdrawals

### ✅ Fixed: Redemption Expiry Bypass
**Issue:** Oracle could finalize expired requests (double-redemption)  
**Fix:** Added expiry check in `finalizeRedemption()`

### ✅ Fixed: Decimal Precision Loss
**Issue:** 18→6 decimal conversion lost fractional cents  
**Fix:** Round up to favor users (never underpay)

### ✅ Fixed: Missing Request Tracking
**Issue:** Users couldn't query their pending redemptions  
**Fix:** Added `getUserRequests()` and `getPendingRequests()`

### ✅ Fixed: StockToken Redemption Integration
**Issue:** `requestRedemption()` only emitted event  
**Fix:** Integrated with RedemptionManager (optional, configurable)

### ✅ Fixed: Missing Backing Verification
**Issue:** Minting had no oracle attestation  
**Fix:** Added optional attestation oracle integration

---

## Intentional Design Decisions

### Why Attestation is Optional
**Reason:** Requires Chainlink Functions, custody setup, operational infrastructure  
**Tutorial Value:** Demonstrates pattern without deployment complexity  
**Production:** MUST enable (`setRequireAttestation(true)`)

### Why No Multi-Sig
**Reason:** Requires operational processes, key management, governance framework  
**Tutorial Value:** Focuses on token logic, not operational overhead  
**Production:** MUST use Gnosis Safe or equivalent

### Why No Rate Limiting
**Reason:** Adds complexity without teaching core RWA patterns  
**Tutorial Value:** Keeps code focused on identity + compliance + redemption  
**Production:** MUST implement daily/weekly caps

### Why No Upgradeability
**Reason:** Proxy patterns are well-documented elsewhere  
**Tutorial Value:** Simpler deployment and testing  
**Production:** MUST use UUPS with timelock

---

## When to Consult an Expert

You MUST seek professional help if you plan to:

- Deploy with real assets (stocks, bonds, real estate)
- Handle real user funds (>$10k TVL)
- Offer tokens to US persons (SEC jurisdiction)
- Integrate with real brokerages or custodians
- Implement full KYC/AML compliance
- Launch in any regulated jurisdiction

**Why?**
- Securities laws vary by jurisdiction and are complex
- A single mistake can result in criminal charges
- Regulatory compliance requires ongoing operational overhead
- Custody and brokerage require licensed partners
- Economic attacks can drain all funds if safeguards are missing

---

## Production Deployment Requirements

### Minimum Viable Production (9-12 months, $500k-$2M)

1. **Security Audits** (2-3 audits, $150k-$400k)
2. **Multi-Sig Setup** (Gnosis Safe 3-of-5)
3. **Timelock** (48hr minimum for upgrades)
4. **Qualified Custodian** (Fireblocks, Coinbase Custody)
5. **Licensed KYC Provider** (Chainalysis, Sumsub)
6. **Legal Entity** (LLC, Foundation)
7. **Regulatory Registration** (SEC, FinCEN)
8. **Insurance** (D&O, cyber, custody, smart contract)
9. **24/7 Monitoring** (Alerting, incident response)
10. **Economic Safeguards** (Circuit breakers, reserve fund)

---

## Use This Tutorial To:

- ✅ Learn RWA tokenization architecture
- ✅ Understand identity + compliance patterns
- ✅ Prototype and experiment safely
- ✅ Build proof-of-concepts
- ✅ Prepare for production (with expert guidance)

## Do NOT Use This Tutorial To:

- ❌ Launch with real assets (without modifications)
- ❌ Handle real user funds (without audits)
- ❌ Claim regulatory compliance (without legal review)
- ❌ Deploy to mainnet (without infrastructure)

---

## Questions?

If you're building a production RWA protocol and need help with:
- Architecture review
- Security hardening
- Regulatory compliance
- Custody integration
- Economic modeling
- Operational infrastructure

**You know where to find me.** 🐴

---

**This tutorial teaches the architecture. Production requires the infrastructure.**
