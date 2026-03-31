# Troubleshooting Guide

## Problem: Dependencies Not Found

If you see errors like:
```
Error (6275): Source "@openzeppelin/contracts/access/Ownable.sol" not found
Error (6275): Source "forge-std/Test.sol" not found
```

This means the dependencies aren't installed.

## Solution: Install Dependencies

### Option 1: Run the installation script

```bash
chmod +x install-deps.sh
./install-deps.sh
```

### Option 2: Manual installation

```bash
# 1. Initialize git (required for forge install)
git init
git add .
git commit -m "Initial commit"

# 2. Install OpenZeppelin contracts
forge install OpenZeppelin/openzeppelin-contracts@v5.0.0

# 3. Install forge-std
forge install foundry-rs/forge-std

# 4. Verify installations
ls lib/
# Should show: forge-std  openzeppelin-contracts

# 5. Build
forge build
```

## Verify Installation

After installation, you should have:

```
rwa-tutorial/
├── lib/
│   ├── forge-std/
│   └── openzeppelin-contracts/
├── foundry.toml (with remappings)
└── src/
```

Check `foundry.toml` contains:

```toml
remappings = [
    "@openzeppelin/contracts/=lib/openzeppelin-contracts/contracts/",
    "forge-std/=lib/forge-std/src/"
]
```

## Common Issues

### Issue 1: Git not initialized

**Error:** `forge install` fails silently

**Solution:**
```bash
git init
git add .
git commit -m "Initial commit"
```

### Issue 2: Wrong OpenZeppelin version

**Error:** Import paths don't match

**Solution:** We're using OpenZeppelin v5.0.0. If you have a different version:
```bash
rm -rf lib/openzeppelin-contracts
forge install OpenZeppelin/openzeppelin-contracts@v5.0.0
```

### Issue 3: Remappings not working

**Error:** Still can't find imports after installation

**Solution:** Check `foundry.toml` has correct remappings:
```toml
remappings = [
    "@openzeppelin/contracts/=lib/openzeppelin-contracts/contracts/",
    "forge-std/=lib/forge-std/src/"
]
```

Or create `remappings.txt` in project root:
```
@openzeppelin/contracts/=lib/openzeppelin-contracts/contracts/
forge-std/=lib/forge-std/src/
```

## Testing the Build

### Step 1: Clean build
```bash
forge clean
forge build
```

Expected output:
```
[⠊] Compiling...
[⠒] Compiling 20 files with Solc 0.8.25
[⠆] Solc 0.8.25 finished in X.XXms
Compiler run successful!
```

### Step 2: Run tests
```bash
forge test -vv
```

Expected output:
```
Running X tests for test/unit/IdentityRegistryTest.t.sol:IdentityRegistryTest
[PASS] test_Deployment() (gas: XXXX)
[PASS] test_RegisterIdentity() (gas: XXXX)
...
Test result: ok. X passed; 0 failed; 0 skipped; finished in X.XXs
```

### Step 3: Run specific test file
```bash
forge test --match-contract IdentityRegistryTest -vv
forge test --match-contract ModularComplianceTest -vv
forge test --match-contract StockTokenTest -vv
```

## If Build Still Fails

1. **Check Solidity version:**
   ```bash
   forge --version
   # Should show: forge 0.2.0 or later
   ```

2. **Check file structure:**
   ```bash
   tree -L 2 src/
   # Should show all .sol files
   ```

3. **Check for syntax errors:**
   ```bash
   forge build 2>&1 | grep "Error"
   # Shows only error lines
   ```

4. **Clean and rebuild:**
   ```bash
   forge clean
   rm -rf out cache
   forge build
   ```

## Getting Help

If you're still having issues:

1. **Check exact error message:**
   ```bash
   forge build 2>&1 | tee build.log
   # Saves full output to build.log
   ```

2. **Verify dependencies:**
   ```bash
   ls -la lib/
   ls -la lib/openzeppelin-contracts/contracts/access/
   ls -la lib/forge-std/src/
   ```

3. **Check Foundry installation:**
   ```bash
   which forge
   forge --version
   ```

## Expected Final State

After successful installation and build:

```
✓ Dependencies installed (lib/ directory exists)
✓ Remappings configured (foundry.toml)
✓ Build succeeds (forge build)
✓ Tests pass (forge test)
```

## Quick Start (Clean Install)

```bash
# From project root
git init
git add .
git commit -m "Initial commit"
forge install OpenZeppelin/openzeppelin-contracts@v5.0.0
forge install foundry-rs/forge-std
forge build
forge test
```

If all commands succeed, you're ready to go!
