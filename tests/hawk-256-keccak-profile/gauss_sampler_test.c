/*
 * Standalone correctness test for the new gauss_sampler.sv hardware CDT
 * sampler (keccak_ip/rtl/gauss_sampler.sv), comparing it directly against
 * a hand-copied reference of hawk_sign.c's sig_gauss() inner loop (the
 * per-block "extract 40 bytes -> compute 4 samples" work that the hardware
 * now offloads), for a single lane (bitbase = 0, as if j = 0).
 *
 * Both paths absorb the exact same seed into their own shake_context via
 * the real hardware-accelerated shake_inject()/shake_flip() (sha3.c) --
 * already proven correct by the full HAWK-256 KAT -- so this test isolates
 * ONLY the new sampler logic: does it reproduce the same x[] samples and
 * squared norm as sig_gauss()'s C math, given the identical SHAKE256
 * byte stream and the identical t[] parity bits?
 *
 * Links only sha3.c (plus bare-metal startup), same as
 * keccak_interleave_test.c / keccak_squeeze_multiblock_test.c.
 */

#include <stddef.h>
#include <stdint.h>
#include <string.h>

#include "uart.h"
#include "sha3.h"
#include "keccak_axi.h"

#define KECCAK_AXI_BASE_ADDR 0x50000000UL

/* HAWK-256 sig_gauss() CDT tables, copied verbatim from hawk_sign.c. */
static const uint16_t tab_hi[] = {
	0x4D70, 0x268B, 0x0F80, 0x04FA, 0x0144, 0x0041, 0x000A, 0x0001
};
#define HI_LEN  ((sizeof tab_hi) / sizeof(uint16_t))

static const uint64_t tab_lo[] = {
	0x71FBD58485D45050, 0x1408A4B181C718B1,
	0x54114F1DC2FA7AC9, 0x614569CC54722DC9,
	0x42F74ADDA0B5AE61, 0x151C5CDCBAFF49A3,
	0x252E2152AB5D758B, 0x23460C30AC398322,
	0x0FDE62196C1718FC, 0x01355A8330C44097,
	0x00127325DDF8CEBA, 0x0000DC8DE401FD12,
	0x000008100822C548, 0x0000003B0FFB28F0,
	0x0000000152A6E9AE, 0x0000000005EFCD99,
	0x000000000014DA4A, 0x0000000000003953,
	0x000000000000007B, 0x0000000000000000
};
#define LO_LEN  ((sizeof tab_lo) / sizeof(uint64_t))

static inline uint64_t
dec64le(const uint8_t *b)
{
	uint64_t v = 0;
	for (int i = 0; i < 8; i++) v |= (uint64_t)b[i] << (8 * i);
	return v;
}

static inline uint16_t
dec16le(const uint8_t *b)
{
	return (uint16_t)(b[0] | (b[1] << 8));
}

/*
 * Reference implementation: hand-copied from hawk_sign.c's sig_gauss()
 * non-AVX2 inner loop (one lane's worth, for NBLOCKS 40-byte squeeze
 * blocks == 4*NBLOCKS samples), bitbase folded in exactly as sig_gauss()
 * folds in 4*j.
 */
static uint32_t
sw_reference(shake_context *sc, unsigned nblocks, unsigned bitbase,
    const uint8_t *t, int8_t *x)
{
	uint32_t sn = 0;

	for (unsigned block = 0; block < nblocks; block++) {
		uint8_t buf[40];
		shake_extract(sc, buf, sizeof buf);

		for (unsigned k = 0; k < 4; k++) {
			unsigned v = bitbase + block * 16 + k;
			uint64_t lo = dec64le(buf + (k << 3));
			uint32_t hi = dec16le(buf + 32 + (k << 1));

			uint32_t neg = -(uint32_t)(lo >> 63);
			lo &= 0x7FFFFFFFFFFFFFFFULL;
			hi &= 0x7FFF;

			uint32_t pbit = (t[v >> 3] >> (v & 7)) & 1;
			uint64_t p_odd = -(uint64_t)pbit;
			uint32_t p_oddw = (uint32_t)p_odd;

			uint32_t r = 0;
			for (size_t i = 0; i < HI_LEN; i += 2) {
				uint64_t tlo0 = tab_lo[i + 0];
				uint64_t tlo1 = tab_lo[i + 1];
				uint64_t tlo = tlo0 ^ (p_odd & (tlo0 ^ tlo1));
				uint32_t cc = (uint32_t)((lo - tlo) >> 63);
				uint32_t thi0 = tab_hi[i + 0];
				uint32_t thi1 = tab_hi[i + 1];
				uint32_t thi = thi0 ^ (p_oddw & (thi0 ^ thi1));
				r += (hi - thi - cc) >> 31;
			}
			uint32_t hinz = (hi - 1) >> 31;
			for (size_t i = HI_LEN; i < LO_LEN; i += 2) {
				uint64_t tlo0 = tab_lo[i + 0];
				uint64_t tlo1 = tab_lo[i + 1];
				uint64_t tlo = tlo0 ^ (p_odd & (tlo0 ^ tlo1));
				uint32_t cc = (uint32_t)((lo - tlo) >> 63);
				r += hinz & cc;
			}

			r = (r << 1) - p_oddw;
			r = (r ^ neg) - neg;

			x[v] = (int8_t)r;
			sn += r * r;
		}
	}
	return sn;
}

static void
hw_sampler_run(shake_context *sc, unsigned nblocks, unsigned bitbase,
    const uint8_t *t, int8_t *x, uint32_t *sn_out)
{
	uint64_t volatile *samp_t_addr =
	    (uint64_t volatile *)(KECCAK_AXI_BASE_ADDR + KECCAK_SAMP_T_ADDR_REG_OFFSET);
	uint64_t volatile *samp_x_addr =
	    (uint64_t volatile *)(KECCAK_AXI_BASE_ADDR + KECCAK_SAMP_X_ADDR_REG_OFFSET);
	uint64_t volatile *samp_bitbase =
	    (uint64_t volatile *)(KECCAK_AXI_BASE_ADDR + KECCAK_SAMP_BITBASE_REG_OFFSET);
	uint64_t volatile *samp_nblocks =
	    (uint64_t volatile *)(KECCAK_AXI_BASE_ADDR + KECCAK_SAMP_NBLOCKS_REG_OFFSET);
	uint64_t volatile *samp_ctrl =
	    (uint64_t volatile *)(KECCAK_AXI_BASE_ADDR + KECCAK_SAMP_CTRL_REG_OFFSET);
	uint64_t volatile *samp_sn =
	    (uint64_t volatile *)(KECCAK_AXI_BASE_ADDR + KECCAK_SAMP_SN_REG_OFFSET);

	/*
	 * sc must already be hardware-resident and shake_flip()-padded
	 * (not yet permuted) -- true here since the caller's most recent
	 * accelerator touch was shake_flip(sc) and nothing else has used
	 * the accelerator since.
	 */
	__asm__ volatile ("fence" ::: "memory");

	/*
	 * SAMP_X_ADDR is "the first output sample byte for this job", i.e.
	 * the caller's x + 4*j (x + bitbase here) -- the hardware only adds
	 * block*16+k on top of it, mirroring sig_gauss()'s x[bitbase +
	 * block*16 + k] indexing.
	 */
	*samp_t_addr  = (uint64_t)(uintptr_t)t;
	*samp_x_addr  = (uint64_t)(uintptr_t)(x + bitbase);
	*samp_bitbase = bitbase;
	*samp_nblocks = nblocks;

	*samp_ctrl = (uint64_t)1 << KECCAK_SAMP_CTRL_GO_BIT;
	while (((*samp_ctrl) & ((uint64_t)1 << KECCAK_SAMP_CTRL_DONE_BIT)) == 0);

	*sn_out = (uint32_t)(*samp_sn);

	*samp_ctrl = 0;

	/*
	 * Required: the sampler writes x[] directly to memory as a second
	 * AXI master, bypassing the CPU's D$ entirely. With
	 * DcacheFlushOnFence/DcacheInvalidateOnFlush enabled in this SoC's
	 * CVA6 config, this fence flushes and invalidates the D$ so the
	 * caller's subsequent normal loads of x[] see the sampler's write
	 * instead of a stale cached value from any earlier CPU access to
	 * the same cache line (e.g. the caller's own memset()).
	 */
	__asm__ volatile ("fence" ::: "memory");

	/* sc's dptr bookkeeping is irrelevant after this -- discarded like
	   sig_gauss()'s own per-j local sc. */
	(void)sc;
}

#define NBLOCKS 32u   /* HAWK-256: n/8 = 32 blocks -> 128 samples per lane */

/*
 * v = bitbase + block*16 + k spans the FULL 2*n = 512-byte output range
 * (one lane's samples are strided every 16 bytes across it, matching
 * sig_gauss()'s 4-lane interleave -- not packed contiguously), even
 * though a single lane only ever writes 128 of those 512 bytes.
 */
#define XBUF_SIZE 512u

static const uint8_t seed[41] = {
	0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07,
	0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f,
	0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17,
	0x18, 0x19, 0x1a, 0x1b, 0x1c, 0x1d, 0x1e, 0x1f,
	0x20, 0x21, 0x22, 0x23, 0x24, 0x25, 0x26, 0x27,
	0x28
};

/* Enough bytes for bitbase in {0,4,8,12}, v = bitbase+block*16+k up to
   511 -- arbitrary but deterministic pattern, exercises every bit
   position. */
static uint8_t t_bits[64];

static int8_t x_sw[XBUF_SIZE];
static int8_t x_hw[XBUF_SIZE];

static int
run_case(const char *name, unsigned bitbase)
{
	shake_context sc_sw, sc_hw;
	uint32_t sn_sw, sn_hw;
	int errors = 0;

	memset(x_sw, 0, sizeof x_sw);
	memset(x_hw, 0, sizeof x_hw);

	/*
	 * sw_reference()'s own shake_extract() calls run through the same
	 * physical accelerator and will evict whichever context was
	 * hardware-resident -- so sc_hw's shake_inject()/shake_flip() must
	 * happen AFTER sw_reference() returns, immediately before
	 * hw_sampler_run(), with nothing else touching the accelerator in
	 * between (hw_sampler_run() assumes sc_hw is still the resident,
	 * flip()-padded-but-unpermuted context when it pokes SAMP_CTRL.GO).
	 */
	shake_init(&sc_sw, 256);
	shake_inject(&sc_sw, seed, sizeof seed);
	shake_flip(&sc_sw);
	sn_sw = sw_reference(&sc_sw, NBLOCKS, bitbase, t_bits, x_sw);

	shake_init(&sc_hw, 256);
	shake_inject(&sc_hw, seed, sizeof seed);
	shake_flip(&sc_hw);
	hw_sampler_run(&sc_hw, NBLOCKS, bitbase, t_bits, x_hw, &sn_hw);

	for (unsigned v = 0; v < XBUF_SIZE; v++) {
		if (x_sw[v] != x_hw[v]) {
			errors++;
			printf("  x[%u] mismatch: sw=%d hw=%d\n",
			    v, (int)x_sw[v], (int)x_hw[v]);
		}
	}
	if (sn_sw != sn_hw) {
		errors++;
		printf("  sn mismatch: sw=%u hw=%u\n",
		    (unsigned)sn_sw, (unsigned)sn_hw);
	}

	printf("%s (bitbase=%u): %s (%d mismatches)\n", name, bitbase,
	    errors == 0 ? "OK" : "MISMATCH", errors);
	return errors;
}

int
main(void)
{
	int errors = 0;

	for (unsigned i = 0; i < sizeof t_bits; i++) {
		t_bits[i] = (uint8_t)(i * 37u + 11u);
	}

	printf("Gaussian CDT sampler hardware-vs-software test\n");

	errors += run_case("j=0 (bitbase=0)", 0);
	errors += run_case("j=1 (bitbase=4)", 4);
	errors += run_case("j=2 (bitbase=8)", 8);
	errors += run_case("j=3 (bitbase=12)", 12);

	if (errors == 0)
		printf("Gaussian sampler test terminated with no errors.\n");
	else
		printf("Gaussian sampler test terminated with %d total mismatches\n", errors);

	return 0;
}
