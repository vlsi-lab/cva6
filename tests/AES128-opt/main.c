///////////////////////////////////////////////////////////////////////////////////////
// Auth: Alessandra Dolmeta, Valeria Piscopo
// @ EDGE group, at VLSI-LAB, Politecnico di Torino
// Desc: AES-128 forward-encrypt KAT + CTR-chain benchmark -- accelerated (aes_ip)
///////////////////////////////////////////////////////////////////////////////////////

// === Same KAT/benchmark as ../AES128/, but calling the aes_ip AXI
//     accelerator (aes_hal.h) instead of software AES-128 -- compare the two
//     runs' [CLK] cycle counts for the speedup. Also checks aes_hal.h's
//     output against the SAME software AES-128 (aes.c, copied here just for
//     this correctness cross-check, not for its own timing) to catch a
//     hw/sw divergence directly, not just a KAT mismatch.

#include <stdint.h>
#include <string.h>
#include <stdio.h>

#include "inc/uart.h"
#include "encoding.h"

#include "aes.h"        // software AES-128, used here only as a correctness cross-check
#include "aes_hal.h"    // aes128_set_key_hw() / aes128_encrypt_block_hw()

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
    uint8_t hw_ct[16], sw_ct[16];
    aes_round_keys_t rk;
    int cycles;
    int fails = 0;

    printf("AES-128 hw benchmark (tests/AES128-opt, aes_ip accelerator)\n");

    // sw cross-check, not timed
    aes128_init_round_keys(&rk, AES_KAT_KEY);
    aes128_encrypt_block(&rk, AES_KAT_PT, sw_ct);

    clear_csr(mcountinhibit, 1);
    write_csr(mcycle, 0);
    aes128_set_key_hw(AES_KAT_KEY);
    aes128_encrypt_block_hw(AES_KAT_PT, hw_ct);
    cycles = read_csr(mcycle);
    printf("[CLK] aes-128 %d hw aes128_encrypt_block_hw()\n", cycles);

    if (memcmp(hw_ct, AES_KAT_CT, 16)) {
        printf("[FAIL] KAT mismatch\n");
        fails++;
    }
    if (memcmp(hw_ct, sw_ct, 16)) {
        printf("[FAIL] hw/sw output mismatch\n");
        fails++;
    }

    // CTR-mode chain with hw auto-increment
    {
        uint8_t iv[16] = { 0 };
        uint8_t out[16 * CTR_CHAIN_BLOCKS];

        write_csr(mcycle, 0);
        aes128_ctr_blocks_hw(iv, out, CTR_CHAIN_BLOCKS);
        cycles = read_csr(mcycle);
        printf("[CLK] aes-128-ctr %d hw %d-block chain (auto-increment)\n", cycles, CTR_CHAIN_BLOCKS);
    }

    // combined stress: many different keys, each doing a short CTR chain --
    // matches recompute_node()'s/faest_leaf_commit_128()'s real usage
    // pattern in FAEST's BAVC tree-walk (see faest-rash/cwrash's
    // aes_test/main.c, same stress test, same fixed-seed xorshift64 PRNG)
    {
        // n_iters is small by default: cva6's full RV64 SoC simulates far
        // slower per cycle in Verilator than cwrash's pug_rv32 testbench, and
        // each iteration also computes a full sw AES reference for the
        // cross-check (~229045 cycles/block, see the sw benchmark's own
        // [CLK] print in ../AES128) -- override via
        // -DAES128_OPT_STRESS_ITERS=N for a larger run.
        uint64_t rng_state = 0xC2B2AE3D27D4EB4FULL;
        unsigned int stress_fails = 0;
#ifndef AES128_OPT_STRESS_ITERS
#define AES128_OPT_STRESS_ITERS 5
#endif
        const unsigned int n_iters = AES128_OPT_STRESS_ITERS;
        const unsigned int n_blocks = 4;
        unsigned int iter;

        write_csr(mcycle, 0);
        for (iter = 0; iter < n_iters; iter++) {
            uint8_t key[16], iv[16];
            uint8_t sw_out[16 * 4], hw_out[16 * 4];
            aes_round_keys_t rk2;
            uint8_t sw_iv[16];
            unsigned int b;
            int i;

            for (i = 0; i < 16; i += 8) {
                rng_state ^= rng_state << 13; rng_state ^= rng_state >> 7; rng_state ^= rng_state << 17;
                memcpy(key + i, &rng_state, 8);
                rng_state ^= rng_state << 13; rng_state ^= rng_state >> 7; rng_state ^= rng_state << 17;
                memcpy(iv + i, &rng_state, 8);
            }

            aes128_init_round_keys(&rk2, key);
            memcpy(sw_iv, iv, 16);
            for (b = 0; b < n_blocks; b++) {
                aes128_encrypt_block(&rk2, sw_iv, sw_out + 16 * b);
                ctr_increment_iv(sw_iv);
            }

            aes128_set_key_hw(key);
            aes128_ctr_blocks_hw(iv, hw_out, n_blocks);

            if (memcmp(sw_out, hw_out, sizeof(sw_out))) {
                stress_fails++;
                printf("[FAIL] key+ctr stress iter %u: sw/hw mismatch\n", iter);
            }
        }
        cycles = read_csr(mcycle);
        printf("[CLK] aes-128-key-ctr-stress %d hw %u iterations\n", cycles, n_iters);
        printf("[INFO] aes-128 key+ctr-stress: %u/%u bit-exact\n", n_iters - stress_fails, n_iters);
        fails += stress_fails;
    }

    if (fails == 0) printf("Test Successful (AES-128 hw KAT, sw/hw bit-exact)\n");
    else             printf("Test FAILED: %d mismatch(es)\n", fails);

    return fails != 0;
}
