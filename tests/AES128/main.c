///////////////////////////////////////////////////////////////////////////////////////
// Auth: Alessandra Dolmeta, Valeria Piscopo
// @ EDGE group, at VLSI-LAB, Politecnico di Torino
// Desc: AES-128 forward-encrypt KAT + CTR-chain benchmark -- PURE SOFTWARE baseline
///////////////////////////////////////////////////////////////////////////////////////

// === Standalone AES-128 encrypt benchmark, software-only golden model.
//     Sibling test tests/AES128-opt/ runs the identical KAT/benchmark but
//     calls the aes_ip accelerator instead -- compare the two runs'
//     [CLK]-style cycle counts for the speedup. AES_KAT_KEY/PT/CT is
//     FIPS-197 Appendix C.1's standard AES-128 known-answer vector.
//
//     aes.c/fields.c/etc. here are copied verbatim from ../FAEST_128F/ (the
//     reference FAEST port already validated on this target, including the
//     unaligned-pointer-cast and heap-sizing fixes documented in
//     ../FAEST.md) -- this directory and ../FAEST_128F/ are NOT the same
//     files on disk, so ../FAEST_128F/ stays untouched.

#include <stdint.h>
#include <string.h>
#include <stdio.h>

#include "inc/uart.h"
#include "encoding.h"

#include "aes.h"

static const uint8_t AES_KAT_KEY[16] = { 0x00,0x01,0x02,0x03,0x04,0x05,0x06,0x07,
                                          0x08,0x09,0x0a,0x0b,0x0c,0x0d,0x0e,0x0f };
static const uint8_t AES_KAT_PT[16]  = { 0x00,0x11,0x22,0x33,0x44,0x55,0x66,0x77,
                                          0x88,0x99,0xaa,0xbb,0xcc,0xdd,0xee,0xff };
static const uint8_t AES_KAT_CT[16]  = { 0x69,0xc4,0xe0,0xd8,0x6a,0x7b,0x04,0x30,
                                          0xd8,0xcd,0xb7,0x80,0x70,0xb4,0xc5,0x5a };

static void ctr_increment_iv(uint8_t iv[16])
{
    uint32_t v = (uint32_t) iv[0] | ((uint32_t) iv[1] << 8) |
                 ((uint32_t) iv[2] << 16) | ((uint32_t) iv[3] << 24);
    v++;
    iv[0] = (uint8_t) v; iv[1] = (uint8_t) (v >> 8);
    iv[2] = (uint8_t) (v >> 16); iv[3] = (uint8_t) (v >> 24);
}

#define CTR_CHAIN_BLOCKS 8

int main(void)
{
    aes_round_keys_t rk;
    uint8_t ct[16];
    int cycles;
    int fails = 0;

    printf("AES-128 sw benchmark (tests/AES128)\n");

    clear_csr(mcountinhibit, 1);
    write_csr(mcycle, 0);
    aes128_init_round_keys(&rk, AES_KAT_KEY);
    aes128_encrypt_block(&rk, AES_KAT_PT, ct);
    cycles = read_csr(mcycle);
    printf("[CLK] aes-128 %d sw aes128_encrypt_block()\n", cycles);

    if (memcmp(ct, AES_KAT_CT, 16)) {
        printf("[FAIL] KAT mismatch\n");
        fails++;
    }

    // CTR-mode chain, same pattern the accelerated test compares against
    {
        uint8_t iv[16] = { 0 };
        uint8_t out[16 * CTR_CHAIN_BLOCKS];
        int i;

        write_csr(mcycle, 0);
        for (i = 0; i < CTR_CHAIN_BLOCKS; i++) {
            aes128_encrypt_block(&rk, iv, out + 16 * i);
            ctr_increment_iv(iv);
        }
        cycles = read_csr(mcycle);
        printf("[CLK] aes-128-ctr %d sw %d-block chain\n", cycles, CTR_CHAIN_BLOCKS);
    }

    if (fails == 0) printf("Test Successful (AES-128 sw KAT)\n");
    else             printf("Test FAILED: %d mismatch(es)\n", fails);

    return fails != 0;
}
