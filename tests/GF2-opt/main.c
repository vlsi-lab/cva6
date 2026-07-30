///////////////////////////////////////////////////////////////////////////////////////
// Auth: Alessandra Dolmeta, Valeria Piscopo
// @ EDGE group, at VLSI-LAB, Politecnico di Torino
// Desc: GF(2) multiply benchmark -- accelerated (gf2_ip)
///////////////////////////////////////////////////////////////////////////////////////

// === Same benchmark as ../GF2/, but calling the gf2_ip AXI accelerator
//     (gf2_hal.h) instead of fields.c's own software bf128_mul()/
//     bf384_mul_128_inplace() -- compare the two runs' [CLK] cycle counts
//     for the speedup. fields.c here is left completely untouched (still
//     the original bit-serial software, unmodified) -- main.c calls it
//     directly for the "sw" cross-check column and gf2_hal.h directly for
//     "hw", side by side, same structure cwrash/faest-rash's gf2_test uses,
//     rather than adding a dispatch branch inside fields.c itself.
//
//     BF384_WORD is a cwrash-specific fields.h addition not present in this
//     original reference copy -- reimplemented locally here instead of
//     touching fields.h, so ../FAEST_128F/'s and this dir's own fields.{c,h}
//     stay exactly as vendored.

#include <stdint.h>
#include <string.h>
#include <stdio.h>

#include "inc/uart.h"
#include "encoding.h"

#include "fields.h"
#include "gf2_hal.h"

#if defined(HAVE_ATTR_VECTOR_SIZE)
#define BF384_WORD_LOCAL(v, i) (BF_VALUE((v).inner[(i) / 2], (i) % 2))
#else
#define BF384_WORD_LOCAL(v, i) (BF_VALUE(v, i))
#endif

static void bf128_to_words(uint64_t w[2], const bf128_t *v)
{
    w[0] = BF_VALUE(*v, 0);
    w[1] = BF_VALUE(*v, 1);
}

static void words_to_bf128(bf128_t *v, const uint64_t w[2])
{
    BF_VALUE(*v, 0) = w[0];
    BF_VALUE(*v, 1) = w[1];
}

static void bf384_to_words(uint64_t w[6], const bf384_t *v)
{
    int i;
    for (i = 0; i < 6; i++) w[i] = BF384_WORD_LOCAL(*v, i);
}

static void words_to_bf384(bf384_t *v, const uint64_t w[6])
{
    int i;
    for (i = 0; i < 6; i++) BF384_WORD_LOCAL(*v, i) = w[i];
}

int main(void)
{
    bf128_t a, b, sw_res, hw_res_bf;
    bf384_t a384, sw384_res, hw384_res_bf;
    uint64_t hw_a[6], hw_b[2], hw_res[2], hw384_a[6];
    uint8_t buf[16];
    int cycles;
    int fails = 0;
    int i;

    printf("GF(2) multiply hw benchmark (tests/GF2-opt, gf2_ip accelerator)\n");

    memset(buf, 0xA5, sizeof(buf));
    bf128_load(&a, buf);
    memset(buf, 0x5A, sizeof(buf));
    bf128_load(&b, buf);

    // identities, hw path
    {
        bf128_t zero = bf128_zero(), one = bf128_one();
        uint64_t z[2], o[2];
        bf128_to_words(hw_a, &a);
        bf128_to_words(z, &zero);
        gf2_mul128_hw(hw_res, hw_a, z);
        if (hw_res[0] != 0 || hw_res[1] != 0) { printf("[FAIL] x*0 != 0 (hw)\n"); fails++; }

        bf128_to_words(o, &one);
        gf2_mul128_hw(hw_res, hw_a, o);
        {
            uint64_t a_words[2];
            bf128_to_words(a_words, &a);
            if (hw_res[0] != a_words[0] || hw_res[1] != a_words[1]) {
                printf("[FAIL] x*1 != x (hw)\n"); fails++;
            }
        }
    }

    // sw cross-check, not timed
    bf128_mul(&sw_res, &a, &b);

    bf128_to_words(hw_a, &a);
    bf128_to_words(hw_b, &b);
    clear_csr(mcountinhibit, 1);
    write_csr(mcycle, 0);
    for (i = 0; i < 100; i++) {
        gf2_mul128_hw(hw_res, hw_a, hw_b);
    }
    cycles = read_csr(mcycle);
    printf("[CLK] gf2-128 %d hw gf2_mul128_hw() x100 calls\n", cycles);
    printf("[INFO] gf2_mul128_hw cycles/call (avg) = %d\n", cycles / 100);

    words_to_bf128(&hw_res_bf, hw_res);
    if (memcmp(&sw_res, &hw_res_bf, sizeof(sw_res))) {
        printf("[FAIL] gf2-128 sw/hw output mismatch\n"); fails++;
    }

    // GF(2^384)-by-GF(2^128)
    {
        uint8_t buf384[48];
        for (i = 0; i < 48; i++) buf384[i] = (uint8_t) (i + 1);
        bf384_load(&a384, buf384);
        sw384_res = a384;
        bf384_mul_128_inplace(&sw384_res, &b);

        bf384_to_words(hw384_a, &a384);
        write_csr(mcycle, 0);
        gf2_mul384_128_hw(hw384_a, hw_b);
        cycles = read_csr(mcycle);
        printf("[CLK] gf2-384 %d hw gf2_mul384_128_hw()\n", cycles);

        words_to_bf384(&hw384_res_bf, hw384_a);
        if (memcmp(&sw384_res, &hw384_res_bf, sizeof(sw384_res))) {
            printf("[FAIL] gf2-384 sw/hw output mismatch\n"); fails++;
        }
    }

    // stress test: many random operand pairs, both widths
    {
        uint64_t rng_state = 0x9E3779B97F4A7C15ULL;
        unsigned int stress_fails_128 = 0, stress_fails_384 = 0;
        const unsigned int n_iters = 50;
        unsigned int iter;

        write_csr(mcycle, 0);
        for (iter = 0; iter < n_iters; iter++) {
            uint64_t words_a[6], words_b[2];
            bf128_t s_a, s_b, s_res;
            bf384_t s384_a, s384_res;
            uint64_t h_res[2], h384_a[6];
            int j;

            for (j = 0; j < 6; j++) {
                rng_state ^= rng_state << 13; rng_state ^= rng_state >> 7; rng_state ^= rng_state << 17;
                words_a[j] = rng_state;
            }
            for (j = 0; j < 2; j++) {
                rng_state ^= rng_state << 13; rng_state ^= rng_state >> 7; rng_state ^= rng_state << 17;
                words_b[j] = rng_state;
            }

            BF_VALUE(s_a, 0) = words_a[0]; BF_VALUE(s_a, 1) = words_a[1];
            BF_VALUE(s_b, 0) = words_b[0]; BF_VALUE(s_b, 1) = words_b[1];

            bf128_mul(&s_res, &s_a, &s_b);
            gf2_mul128_hw(h_res, words_a, words_b);
            {
                bf128_t h_res_bf;
                words_to_bf128(&h_res_bf, h_res);
                if (memcmp(&s_res, &h_res_bf, sizeof(s_res))) stress_fails_128++;
            }

            for (j = 0; j < 6; j++) BF384_WORD_LOCAL(s384_a, j) = words_a[j];
            s384_res = s384_a;
            bf384_mul_128_inplace(&s384_res, &s_b);

            for (j = 0; j < 6; j++) h384_a[j] = words_a[j];
            gf2_mul384_128_hw(h384_a, words_b);
            {
                bf384_t h384_res_bf;
                for (j = 0; j < 6; j++) BF384_WORD_LOCAL(h384_res_bf, j) = h384_a[j];
                if (memcmp(&s384_res, &h384_res_bf, sizeof(s384_res))) stress_fails_384++;
            }
        }
        cycles = read_csr(mcycle);
        printf("[CLK] gf2-stress %d hw %u iterations (both widths)\n", cycles, n_iters);
        printf("[INFO] gf2-128 stress: %u/%u bit-exact\n", n_iters - stress_fails_128, n_iters);
        printf("[INFO] gf2-384 stress: %u/%u bit-exact\n", n_iters - stress_fails_384, n_iters);
        fails += stress_fails_128 + stress_fails_384;
    }

    if (fails == 0) printf("Test Successful (GF(2) multiply hw, sw/hw bit-exact)\n");
    else             printf("Test FAILED: %d mismatch(es)\n", fails);

    return fails != 0;
}
