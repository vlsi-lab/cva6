///////////////////////////////////////////////////////////////////////////////////
//
// Copyright 2025 PoliTO - @VLSI Lab
// Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
//
// Auth: Alessandra Dolmeta, Valeria Piscopo
// Email: alessandra.dolmeta@polito.it, valeria.piscopo@polito.it
// Affiliation: Politecnico di Torino - @VLSI Lab
// Date: October 2025
//
///////////////////////////////////////////////////////////////////////////////////
//
// Verify-only KAT test: vrf_ip is a verify-only accelerator, so only
// crypto_sign_open() is exercised here -- keygen/sign are not run (see
// tests/pqc/ for the full keygen+sign+verify baseline/optimized harness).
// The KAT's own pk/sm values are loaded directly instead of generating
// them. Prints both clock cycles and retired instructions for verify.
//

#include <stdio.h>
#include <string.h>
#include "api.h"
#include "encoding.h"

#include "test_vectors_shake256_256f_simple.h"

#define MLEN_KAT 33

#define CRYPTO_PUBLICKEYBYTES SPX_PK_BYTES
#define CRYPTO_BYTES SPX_BYTES

int main(void)
{
    uint8_t pk[CRYPTO_PUBLICKEYBYTES];
    uint8_t sm[MLEN_KAT + CRYPTO_BYTES];
    uint8_t m1[MLEN_KAT + CRYPTO_BYTES];

    unsigned long long mlen1;
    unsigned cycles, instrs, start_instret;

    clear_csr(mcountinhibit, 1);

    memcpy(pk, TVEC_OUT_PK, CRYPTO_PUBLICKEYBYTES);
    memcpy(sm, TVEC_IN_SM_SIGN, MLEN_KAT + CRYPTO_BYTES);

    write_csr(mcycle, 0);
    start_instret = (uint32_t)read_csr(minstret);

    crypto_sign_open(m1, &mlen1, sm, MLEN_KAT + CRYPTO_BYTES, pk);

    cycles = (uint32_t)read_csr(mcycle);
    instrs = (uint32_t)read_csr(minstret) - start_instret;
    printf("Clock cycles [verify]: %u\n", cycles);
    printf("Instructions [verify]: %u\n", instrs);

    if (mlen1 != MLEN_KAT || memcmp(m1, TVEC_IN_M_SIGN, MLEN_KAT)) {
        printf("ERROR: M mismatch\n");
        printf("Test Failed\n");
        return 1;
    }

    printf("Test Successful\n");
    return 0;
}
