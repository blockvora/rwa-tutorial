#!/bin/bash

echo "Installing dependencies for rwa-tutorial..."

# Initialize git if not already initialized
if [ ! -d .git ]; then
    echo "Initializing git repository..."
    git init
    git add .
    git commit -m "Initial commit"
fi

# Install OpenZeppelin contracts
echo "Installing OpenZeppelin contracts..."
forge install OpenZeppelin/openzeppelin-contracts@v5.0.0

# Install forge-std
echo "Installing forge-std..."
forge install foundry-rs/forge-std

# Verify installations
echo ""
echo "Checking installations..."
if [ -d "lib/openzeppelin-contracts" ]; then
    echo "✓ OpenZeppelin contracts installed"
else
    echo "✗ OpenZeppelin contracts NOT installed"
fi

if [ -d "lib/forge-std" ]; then
    echo "✓ forge-std installed"
else
    echo "✗ forge-std NOT installed"
fi

echo ""
echo "Building contracts..."
forge build

echo ""
echo "Done! If build succeeded, run: forge test"
