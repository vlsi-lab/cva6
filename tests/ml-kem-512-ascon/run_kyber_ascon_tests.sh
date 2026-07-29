#!/bin/bash

# Script to run Kyber-Ascon tests
# Kyber implementation using Ascon instead of FIPS-202/Keccak

echo "================================================"
echo "Kyber-Ascon Test Suite"
echo "================================================"
echo "Using Ascon XOF/Hash instead of SHA3/SHAKE"
echo "Security Level: 128-bit (Kyber-512 only)"
echo "================================================"

cd "$(dirname "$0")"

echo ""
echo "========================================"
echo "Running Kyber-512-Ascon Test..."
echo "========================================"
./test/test_kyber512_ascon
if [ $? -eq 0 ]; then
    echo "✓ Kyber-512-Ascon test passed"
else
    echo "✗ Kyber-512-Ascon test failed"
    exit 1
fi

echo ""
echo "================================================"
echo "✓ All Kyber-Ascon tests passed successfully!"
echo "================================================"
