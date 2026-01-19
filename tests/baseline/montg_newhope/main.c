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

#define NEWHOPE_Q     12289
#define NEWHOPE_QINV  12287   // -q^{-1} mod 2^16

static inline int16_t montgomery_reduce_newhope(int32_t a) {
  int16_t t;
  t = (int16_t)a * NEWHOPE_QINV;
  t = (a - (int32_t)t * NEWHOPE_Q) >> 16;
  return t;
}


int main(void) {

    // ---------------- NewHope ----------------
    const int32_t nh_inputs[20] = {
      0, 1, -1, 1234567, -1234567, 2147483647, -2147483648, 0x0000FFFF, 0xFFFF0000, 12289, 2*12289, -12289, 2147483647, -2147483648, 9999999, -9999999, 65535, -65535, 12345, -54321
    };
    const int16_t nh_golden[20] = {
      0, -2304, 2303, -5813, 5812, -30465, -32768, 2304, -1, 0, 0, -1, -30465, -32768, -2608, 2607, 2304, -2305, -6134, 4406
    };


    int16_t got_sw[N_TESTS] = {0};
    int kem_ok_sw = 1;
    
    int cycles;
    clear_csr(mcountinhibit, 1);
    write_csr(mcycle, 0);

    for (int i = 0; i < N_TESTS; i++) {
        got_sw[i] = montgomery_reduce_newhope(nh_inputs[i]);
    }

    cycles = read_csr(mcycle);
    printf("montg_kyber [Executed %d tests]: %d\n", N_TESTS, cycles);

    for (int i = 0; i < N_TESTS; i++) {
        if (got_sw[i] != nh_golden[i]) {
            printf("[NEWHOPE] Test %2d FAIL: a=%d  exp=%d  got=%d\n",
                    i, nh_inputs[i], nh_golden[i], got_sw[i]);
            kem_ok_sw = 0;
            }
        }
        
    if (kem_ok_sw) printf("[NEWHOPE] All 20 Montgomery tests PASSED.\n");

    return 0;
}
