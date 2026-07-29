#!/bin/bash

# Script to run Kyber-Ascon KAT (Known Answer Test) generator
# Generates test vectors for Kyber-512-Ascon

echo "================================================"
echo "Kyber-Ascon KAT Generator"
echo "================================================"
echo "Using Ascon XOF/Hash instead of SHA3/SHAKE"
echo "Security Level: 128-bit (Kyber-512 only)"
echo "================================================"

cd "$(dirname "$0")/nistkat"

echo ""
echo "========================================"
echo "Running Kyber-512-Ascon KAT Test..."
echo "========================================"
./PQCgenKAT_kem512_ascon
if [ $? -eq 0 ]; then
    echo "✓ Kyber-512-Ascon KAT test completed successfully"
    echo "  Generated: PQCkemKAT_1632.req and PQCkemKAT_1632.rsp"
else
    echo "✗ Kyber-512-Ascon KAT test failed"
    exit 1
fi

echo ""
echo "================================================"
echo "KAT files generated:"
echo "================================================"
ls -lh *.req *.rsp 2>/dev/null || echo "No KAT files found"
