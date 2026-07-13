#!/bin/bash

# Script to run Dilithium-Ascon KAT (Known Answer Test) generator
# Generates test vectors for Dilithium-2-Ascon

echo "================================================"
echo "Dilithium-Ascon KAT Generator"
echo "================================================"
echo "Using Ascon XOF/Hash instead of SHA3/SHAKE"
echo "Security Level: 128-bit (Dilithium-2 only)"
echo "================================================"

cd "$(dirname "$0")/nistkat"

echo ""
echo "========================================"
echo "Running Dilithium-2-Ascon KAT Test..."
echo "========================================"
./PQCgenKAT_sign2_ascon
if [ $? -eq 0 ]; then
    echo "✓ Dilithium-2-Ascon KAT test completed successfully"
    echo "  Generated: PQCsignKAT_*.req and PQCsignKAT_*.rsp"
else
    echo "✗ Dilithium-2-Ascon KAT test failed"
    exit 1
fi

echo ""
echo "================================================"
echo "KAT files generated:"
echo "================================================"
ls -lh *.req *.rsp 2>/dev/null || echo "No KAT files found"
