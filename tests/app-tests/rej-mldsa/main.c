/*
 * tests/app-tests/rej-mldsa/main.c
 *
 * Standalone SW-vs-HW test for rej_sampler.sv's new ML-DSA mode
 * (REJ_CTRL.CAND3/RATE168/OUTWIDE): a from-scratch SHAKE128 + rej_uniform
 * software reference (3-byte little-endian candidates, masked to 23 bits,
 * reject >= q=8380417, int32_t output -- see
 * tests/pqc/baseline/ML-DSA-44/poly.c's rej_uniform()/poly_uniform() for
 * the algorithm this mirrors) compared against a single rej_sampler HW job
 * with those three mode bits set.
 *
 * Precondition rej_sampler assumes (see rej_sampler.sv's header): the
 * resident DATA[] state must already hold the padded (pad10*1-applied,
 * NOT yet permuted) first rate block before REJ_CTRL.GO is set. This test
 * stages that directly via the legacy CSREG/DATA[] register interface
 * (same pattern as tests/app-tests/keccak-permute), so it exercises
 * rej_sampler's own SHAKE128-rate (168-byte) block-wrap logic standalone,
 * without depending on keccak_dma_ctrl.sv's SHAKE128 absorb support
 * (a separate primitive, tested independently in tests/app-tests/
 * keccak-abs-shake128).
 */

#include <stdint.h>
#include <string.h>

#include "encoding.h"
#include "vrf_axi.h"
#include "uart.h"

#define VRF_AXI_BASE_ADDR 0x50000000UL
#define VRF_REJ_HW_SCRATCH_ADDR 0x80F0A000UL

#define Q          8380417u
#define N_SAMPLES  64u   /* accepted samples to produce -- small enough for a fast sim */
#define RATE128    168u  /* SHAKE128 rate in bytes */

/* ===================================================================== */
/* SW reference: KeccakF1600 + SHAKE128 squeeze + rej_uniform.           */
/* Keccak-f[1600] permutation, same reference form used throughout       */
/* tests/app-tests/ (see e.g. keccak-permute/keccak-permute.c).          */
/* ===================================================================== */

static const uint64_t RC[24] = {
	0x0000000000000001ULL, 0x0000000000008082ULL, 0x800000000000808aULL,
	0x8000000080008000ULL, 0x000000000000808bULL, 0x0000000080000001ULL,
	0x8000000080008081ULL, 0x8000000000008009ULL, 0x000000000000008aULL,
	0x0000000000000088ULL, 0x0000000080008009ULL, 0x000000008000000aULL,
	0x000000008000808bULL, 0x800000000000008bULL, 0x8000000000008089ULL,
	0x8000000000008003ULL, 0x8000000000008002ULL, 0x8000000000000080ULL,
	0x000000000000800aULL, 0x800000008000000aULL, 0x8000000080008081ULL,
	0x8000000000008080ULL, 0x0000000080000001ULL, 0x8000000080008008ULL
};
static const unsigned RHO[24] = {
	 1,  3,  6, 10, 15, 21, 28, 36, 45, 55,  2, 14,
	27, 41, 56,  8, 25, 43, 62, 18, 39, 61, 20, 44
};
static const unsigned PI_[24] = {
	10,  7, 11, 17, 18,  3,  5, 16,  8, 21, 24,  4,
	15, 23, 19, 13, 12,  2, 20, 14, 22,  9,  6,  1
};

static inline uint64_t rol64(uint64_t x, unsigned r) { return (x << r) | (x >> (64u - r)); }

static void
KeccakF1600(uint64_t s[25])
{
	unsigned round, i;
	for (round = 0; round < 24; round++) {
		uint64_t c[5], d[5], b[25], t;
		for (i = 0; i < 5; i++) {
			c[i] = s[i] ^ s[i + 5] ^ s[i + 10] ^ s[i + 15] ^ s[i + 20];
		}
		for (i = 0; i < 5; i++) {
			d[i] = c[(i + 4) % 5] ^ rol64(c[(i + 1) % 5], 1);
		}
		for (i = 0; i < 25; i++) {
			s[i] ^= d[i % 5];
		}
		b[0] = s[0];
		t = s[1];
		for (i = 0; i < 24; i++) {
			unsigned j = PI_[i];
			uint64_t tmp = s[j];
			b[j] = rol64(t, RHO[i]);
			t = tmp;
		}
		for (i = 0; i < 5; i++) {
			unsigned base = i * 5;
			uint64_t a0 = b[base], a1 = b[base + 1], a2 = b[base + 2],
			         a3 = b[base + 3], a4 = b[base + 4];
			s[base]     = a0 ^ (~a1 & a2);
			s[base + 1] = a1 ^ (~a2 & a3);
			s[base + 2] = a2 ^ (~a3 & a4);
			s[base + 3] = a3 ^ (~a4 & a0);
			s[base + 4] = a4 ^ (~a0 & a1);
		}
		s[0] ^= RC[round];
	}
}

/* SW SHAKE128 squeeze-only stream over a small (<rate) seed, matching
 * ML-DSA's stream128_init()+squeezeblocks() usage in rej_uniform's caller
 * (poly_uniform()). */
typedef struct {
	uint64_t s[25];
	unsigned pos; /* next unsqueezed byte offset within the current block */
} shake128_ctx_t;

static void
shake128_init(shake128_ctx_t *ctx, const uint8_t *seed, size_t seed_len)
{
	uint8_t block[RATE128];

	memset(block, 0, sizeof block);
	memcpy(block, seed, seed_len);
	block[seed_len] ^= 0x1F;
	block[RATE128 - 1] ^= 0x80;

	memset(ctx->s, 0, sizeof ctx->s);
	for (unsigned i = 0; i < RATE128; i++) {
		((uint8_t *)ctx->s)[i] ^= block[i];
	}
	KeccakF1600(ctx->s);
	ctx->pos = 0;
}

static uint8_t
shake128_byte(shake128_ctx_t *ctx)
{
	uint8_t b = ((uint8_t *)ctx->s)[ctx->pos++];
	if (ctx->pos == RATE128) {
		KeccakF1600(ctx->s);
		ctx->pos = 0;
	}
	return b;
}

/* rej_uniform(): mirrors tests/pqc/baseline/ML-DSA-44/poly.c exactly
 * (3-byte little-endian candidate, mask to 23 bits, reject >= Q). */
static void
sw_rej_uniform(int32_t *out, unsigned n_want, const uint8_t *seed, size_t seed_len)
{
	shake128_ctx_t ctx;
	unsigned got = 0;

	shake128_init(&ctx, seed, seed_len);
	while (got < n_want) {
		uint32_t t = shake128_byte(&ctx);
		t |= (uint32_t)shake128_byte(&ctx) << 8;
		t |= (uint32_t)shake128_byte(&ctx) << 16;
		t &= 0x7FFFFFu;
		if (t < Q) {
			out[got++] = (int32_t)t;
		}
	}
}

/* ===================================================================== */
/* HW path                                                               */
/* ===================================================================== */

static void
hw_rej_uniform(int32_t *out, unsigned n_want, const uint8_t *seed, size_t seed_len)
{
	uint64_t volatile *data = (uint64_t volatile *)
	    (VRF_AXI_BASE_ADDR + VRF_DATA_0_REG_OFFSET);
	uint64_t volatile *rej_x_addr = (uint64_t volatile *)
	    (VRF_AXI_BASE_ADDR + VRF_REJ_X_ADDR_REG_OFFSET);
	uint64_t volatile *rej_params = (uint64_t volatile *)
	    (VRF_AXI_BASE_ADDR + VRF_REJ_PARAMS_REG_OFFSET);
	uint64_t volatile *rej_ctrl = (uint64_t volatile *)
	    (VRF_AXI_BASE_ADDR + VRF_REJ_CTRL_REG_OFFSET);
	int32_t volatile *scratch = (int32_t volatile *)VRF_REJ_HW_SCRATCH_ADDR;
	uint8_t block[200];
	unsigned i;

	/* Stage the padded first SHAKE128-rate block directly into DATA[]
	 * (pre-permutation, per rej_sampler.sv's precondition). */
	memset(block, 0, sizeof block);
	memcpy(block, seed, seed_len);
	block[seed_len] ^= 0x1F;
	block[RATE128 - 1] ^= 0x80;
	for (i = 0; i < 25; i++) {
		uint64_t w = 0;
		memcpy(&w, block + 8u * i, 8);
		data[i] = w;
	}

	__asm__ volatile ("fence" ::: "memory");

	*rej_x_addr = (uint64_t)VRF_REJ_HW_SCRATCH_ADDR;
	*rej_params = ((uint64_t)Q << VRF_REJ_PARAMS_Q_OFFSET)
	    | ((uint64_t)Q << VRF_REJ_PARAMS_THRESH_OFFSET)
	    | ((uint64_t)n_want << VRF_REJ_PARAMS_N_OFFSET);
	*rej_ctrl = ((uint64_t)1 << VRF_REJ_CTRL_GO_BIT)
	    | ((uint64_t)1 << VRF_REJ_CTRL_CAND3_BIT)
	    | ((uint64_t)1 << VRF_REJ_CTRL_RATE168_BIT)
	    | ((uint64_t)1 << VRF_REJ_CTRL_OUTWIDE_BIT);
	while (((*rej_ctrl) & ((uint64_t)1 << VRF_REJ_CTRL_DONE_BIT)) == 0);
	*rej_ctrl = 0;

	__asm__ volatile ("fence" ::: "memory");

	for (i = 0; i < n_want; i++) {
		out[i] = scratch[i];
	}
}

/* ===================================================================== */
/* Test driver                                                           */
/* ===================================================================== */

int
main(void)
{
	static const uint8_t seed[34] = {
		0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88,
		0x99, 0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF, 0x01,
		0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09,
		0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x10, 0x11,
		0x00, 0x00 /* trailing 2-byte nonce field, like stream128_init() */
	};
	static int32_t out_sw[N_SAMPLES], out_hw[N_SAMPLES];
	uint32_t cycles_sw, cycles_hw;
	unsigned mismatches = 0, i;

	print_uart("=== rej-mldsa: rej_uniform (q=8380417, SHAKE128) SW-vs-HW ===\n");

	clear_csr(mcountinhibit, 1);

	write_csr(mcycle, 0);
	sw_rej_uniform(out_sw, N_SAMPLES, seed, sizeof seed);
	cycles_sw = (uint32_t)read_csr(mcycle);

	write_csr(mcycle, 0);
	hw_rej_uniform(out_hw, N_SAMPLES, seed, sizeof seed);
	cycles_hw = (uint32_t)read_csr(mcycle);

	for (i = 0; i < N_SAMPLES; i++) {
		if (out_sw[i] != out_hw[i]) {
			mismatches++;
		}
		if (out_sw[i] >= (int32_t)Q || out_sw[i] < 0) {
			mismatches++; /* SW self-check: every accepted sample must be in [0,Q) */
		}
	}

	print_uart("SW cycles: ");
	print_uart_dec((int)cycles_sw);
	print_uart("\nHW cycles: ");
	print_uart_dec((int)cycles_hw);
	print_uart("\nMismatches: ");
	print_uart_dec((int)mismatches);
	print_uart("\n");

	if (mismatches == 0) {
		print_uart("FINAL STATUS: ALL TESTS PASSED\n");
	} else {
		print_uart("FINAL STATUS: TEST(S) FAILED\n");
	}

	return mismatches != 0;
}
