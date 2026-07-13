#!/bin/bash

# Script to run Dilithium-Ascon tests
# Dilithium implementation using Ascon instead of FIPS-202/Keccak

echo "================================================"
echo "Dilithium-Ascon Test Suite"
echo "================================================"
echo "Using Ascon XOF/Hash instead of SHA3/SHAKE"
echo "Security Level: 128-bit (Dilithium-2 only)"
echo "================================================"

cd "$(dirname "$0")"

echo ""
echo "========================================"
echo "Running Dilithium-2-Ascon Test..."
echo "========================================"
./test/test_dilithium2_ascon
if [ $? -eq 0 ]; then
    echo "✓ Dilithium-2-Ascon test passed"
else
    echo "✗ Dilithium-2-Ascon test failed"
    exit 1
fi

echo ""
echo "================================================"
echo "✓ All Dilithium-Ascon tests passed successfully!"
echo "================================================"
