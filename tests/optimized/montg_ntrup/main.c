///////////////////////////////////////////////////////////////////////////////////
//
// Copyright 2025 PoliTO - @VLSI Lab
// Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
//
// Generic Montgomery reduction tests for ML-DSA (Dilithium) and ML-KEM (Kyber)
//
///////////////////////////////////////////////////////////////////////////////////

#include <stdint.h>
#include <stdio.h>



#include "inc/uart.h"
#include "encoding.h"

#define N_TESTS  20

// ---------------- NTRU Prime (q = 4591) ----------------
#define NTRUP_Q     4591
#define NTRUP_QINV  49905   // -q^{-1} mod 2^16

#define MONTG_NTRUP(dest, a) \
    asm volatile ( \
        ".insn r 0x7b, 0x1, 0x3, %[rd], %[r1], x0 \n" \
        : [rd] "=&r" (dest) \
        : [r1] "r" (a) \
    );

int main(void) {

    // ---------------- NTRU Prime ----------------
    const int32_t ntrup_inputs[20] = {
        0, 1, -1, 1234567, -1234567, 2147483647, -2147483648, 0x0000FFFF, 0xFFFF0000, 4591, 2*4591, -4591, 2147483647, -2147483648, 9999999, -9999999, 65535, -65535, 12345, -54321
    };
    const int16_t ntrup_golden[20] = {
        0, 1095, -1096, -1185, 1184, 31672, -32768, -1095, -1, 0, 0, -1, 31672, -32768, 519, -520, -1095, 1094, 1871, -501
    };


    int16_t got[N_TESTS] = {0};
    int kem_ok_sw = 1;

    int cycles;
    clear_csr(mcountinhibit, 1);
    write_csr(mcycle, 0);

    for (int i = 0; i < N_TESTS; i++) {
        //got[i] = montgomery_reduce_ntrup(ntrup_inputs[i]);
        MONTG_NTRUP(got[i], ntrup_inputs[i]);
    }

    cycles = read_csr(mcycle);
    printf("montg_ntrup [Executed %d tests]: %d\n", N_TESTS, cycles);


    for (int i = 0; i < N_TESTS; i++) {
        if (got[i] != ntrup_golden[i]) {
            printf("[NTRU-P] Test %2d FAIL: a=%d  exp=%d  got=%d\n",
                    i, ntrup_inputs[i], ntrup_golden[i], got[i]);
            kem_ok_sw = 0;
            }
        }
        
    if (kem_ok_sw) printf("[NTRU-P] All 20 Montgomery tests PASSED.\n");

    return 0;
}
