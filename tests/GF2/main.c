///////////////////////////////////////////////////////////////////////////////////////
// Auth: Alessandra Dolmeta, Valeria Piscopo
// @ EDGE group, at VLSI-LAB, Politecnico di Torino
// Desc: GF(2) multiply benchmark -- PURE SOFTWARE baseline (fields.c's own algorithm)
///////////////////////////////////////////////////////////////////////////////////////

// === Standalone GF(2^128)/GF(2^384)-by-GF(2^128) multiply benchmark,
//     software only. There's no widely published KAT vector for FAEST's
//     specific field representation, so correctness rests on two
//     hand-verifiable identities (x*0==0, x*1==x) -- same approach
//     cwrash/faest-rash's gf2_test uses. Sibling test ../GF2-opt/ runs the
//     identical benchmark calling the gf2_ip accelerator instead.
//
//     fields.c here is copied verbatim from ../FAEST_128F/ (see AES128's
//     header comment for why) -- NOT the windowed/hw-dispatchable version
//     from cwrash, so this measures fields.c's ORIGINAL bit-serial
//     algorithm as the "before any optimization" baseline. (The windowed
//     software algorithm and hw dispatch itself are cwrash-side work not
//     yet ported into FAEST's own sources here -- see this repo's
//     FAEST_ACCEL.md "Not yet done" section.)

#include <stdint.h>
#include <string.h>
#include <stdio.h>

#include "inc/uart.h"
#include "encoding.h"

#include "fields.h"

int main(void)
{
    bf128_t a, b, r, zero, one;
    bf384_t a384, r384;
    uint8_t buf[16];
    int cycles;
    int fails = 0;
    int i;

    printf("GF(2) multiply sw benchmark (tests/GF2)\n");

    memset(buf, 0xA5, sizeof(buf));
    bf128_load(&a, buf);
    memset(buf, 0x5A, sizeof(buf));
    bf128_load(&b, buf);
    zero = bf128_zero();
    one  = bf128_one();

    // identity 1: x*0 == 0
    bf128_mul(&r, &a, &zero);
    if (memcmp(&r, &zero, sizeof(r))) { printf("[FAIL] x*0 != 0\n"); fails++; }

    // identity 2: x*1 == x
    bf128_mul(&r, &a, &one);
    if (memcmp(&r, &a, sizeof(r))) { printf("[FAIL] x*1 != x\n"); fails++; }

    clear_csr(mcountinhibit, 1);
    write_csr(mcycle, 0);
    for (i = 0; i < 100; i++) {
        bf128_mul(&r, &a, &b);
    }
    cycles = read_csr(mcycle);
    printf("[CLK] gf2-128 %d sw bf128_mul() x100 calls\n", cycles);
    printf("[INFO] bf128_mul cycles/call (avg) = %d\n", cycles / 100);

    // GF(2^384)-by-GF(2^128)
    {
        uint8_t buf384[48];
        for (i = 0; i < 48; i++) buf384[i] = (uint8_t) (i + 1);
        bf384_load(&a384, buf384);
        r384 = a384;

        write_csr(mcycle, 0);
        bf384_mul_128_inplace(&r384, &b);
        cycles = read_csr(mcycle);
        printf("[CLK] gf2-384 %d sw bf384_mul_128_inplace()\n", cycles);
    }

    if (fails == 0) printf("Test Successful (GF(2) multiply sw)\n");
    else             printf("Test FAILED: %d mismatch(es)\n", fails);

    return fails != 0;
}
