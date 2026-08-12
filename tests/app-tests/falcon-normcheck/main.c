/*
 * tests/app-tests/falcon-normcheck/main.c
 *
 * Standalone SW-vs-HW test for falcon_normcheck.sv (Zf(is_short)() offload,
 * vrf_ip/rtl/falcon_normcheck.sv). Independent, from-scratch software
 * reimplementation (sw_is_short below) of the reference's squared-l2-norm
 * check -- sum(s1[u]^2) + sum(s2[u]^2), with the reference's exact
 * constant-time saturating-overflow trick (`ng |= s; ... s |= -(ng>>31)`)
 * -- not copy-pasted from common.c, so a hardware bug and a "copied the
 * same mistake" software bug can't both produce a false PASS.
 *
 * Unlike falcon_decode.sv, this job never writes to memory (its only
 * output is a single pass/fail bit in NORMCHECK_CTRL), so there is no
 * D-cache-staleness concern here -- both s1[]/s2[] are read-only inputs
 * to the accelerator, ordered by a plain `fence` before dispatch, same as
 * every other job's input on this accelerator.
 *
 * Covers: a realistic random coefficient pair with a real Falcon-512
 * l2bound[logn] threshold, an exact-boundary case (bound == sum and
 * bound == sum-1, testing the reference's inclusive `<=`), an
 * accumulator-overflow case (large coefficients forcing the sticky
 * saturation path), and the n=0 edge case.
 */

#include <stdint.h>
#include <string.h>

#include "encoding.h"
#include "vrf_axi.h"
#include "uart.h"

#define VRF_AXI_BASE_ADDR 0x50000000UL

#define N 512

/* real Falcon-512 (logn=9) threshold, common.c's l2bound[9] */
#define L2BOUND_LOGN9 34034726u

/* ===================================================================== */
/* SW reference: independently derived from the documented algorithm.    */
/* ===================================================================== */

static int
sw_is_short(const int16_t *s1, const int16_t *s2, unsigned n, uint32_t bound)
{
	uint32_t s = 0, ng = 0;
	unsigned u;

	for (u = 0; u < n; u++) {
		int32_t z;

		z = s1[u];
		s += (uint32_t)(z * z);
		ng |= s;
		z = s2[u];
		s += (uint32_t)(z * z);
		ng |= s;
	}
	s |= (uint32_t)(-(int32_t)(ng >> 31));

	return s <= bound;
}

/* ===================================================================== */
/* HW dispatch                                                            */
/* ===================================================================== */

static int
hw_is_short(const int16_t *s1, const int16_t *s2, unsigned n, uint32_t bound)
{
	uint64_t volatile *normcheck_s1_addr = (uint64_t volatile *)
	    (VRF_AXI_BASE_ADDR + VRF_NORMCHECK_S1_ADDR_REG_OFFSET);
	uint64_t volatile *normcheck_s2_addr = (uint64_t volatile *)
	    (VRF_AXI_BASE_ADDR + VRF_NORMCHECK_S2_ADDR_REG_OFFSET);
	uint64_t volatile *normcheck_bound = (uint64_t volatile *)
	    (VRF_AXI_BASE_ADDR + VRF_NORMCHECK_BOUND_REG_OFFSET);
	uint64_t volatile *normcheck_ctrl = (uint64_t volatile *)
	    (VRF_AXI_BASE_ADDR + VRF_NORMCHECK_CTRL_REG_OFFSET);
	uint64_t ctrl_val;
	int pass;

	__asm__ volatile ("fence" ::: "memory");

	*normcheck_s1_addr = (uint64_t)(uintptr_t)s1;
	*normcheck_s2_addr = (uint64_t)(uintptr_t)s2;
	*normcheck_bound   = (uint64_t)bound;
	*normcheck_ctrl = ((uint64_t)1 << VRF_NORMCHECK_CTRL_GO_BIT)
	    | ((uint64_t)n << VRF_NORMCHECK_CTRL_N_OFFSET);

	while (((*normcheck_ctrl) & ((uint64_t)1 << VRF_NORMCHECK_CTRL_DONE_BIT)) == 0);

	ctrl_val = *normcheck_ctrl;
	pass = (ctrl_val & ((uint64_t)1 << VRF_NORMCHECK_CTRL_PASS_BIT)) != 0;

	*normcheck_ctrl = 0;

	__asm__ volatile ("fence" ::: "memory");

	return pass;
}

/* ===================================================================== */
/* Test driver                                                            */
/* ===================================================================== */

static int16_t s1_buf[N];
static int16_t s2_buf[N];

static uint32_t
xorshift32(uint32_t *state)
{
	uint32_t x = *state;
	x ^= x << 13;
	x ^= x >> 17;
	x ^= x << 5;
	*state = x;
	return x;
}

static void
fill_random(int16_t *buf, unsigned n, uint32_t *rng, int32_t max_mag)
{
	unsigned i;
	for (i = 0; i < n; i++) {
		int32_t mag = (int32_t)(xorshift32(rng) % (uint32_t)(max_mag + 1));
		int sign = xorshift32(rng) & 1;
		buf[i] = (int16_t)(sign ? -mag : mag);
	}
}

static int
run_random_case(void)
{
	uint32_t rng = 0xC0FFEEu;
	int sw_pass, hw_pass;

	/* magnitudes distributed like real Falcon-512 signature coefficients
	 * (well under the 2047 encode/decode bound). */
	fill_random(s1_buf, N, &rng, 200);
	fill_random(s2_buf, N, &rng, 200);

	sw_pass = sw_is_short(s1_buf, s2_buf, N, L2BOUND_LOGN9);
	hw_pass = hw_is_short(s1_buf, s2_buf, N, L2BOUND_LOGN9);

	print_uart("random-512 (l2bound[9]): sw=");
	print_uart(sw_pass ? "PASS" : "FAIL");
	print_uart(" hw=");
	print_uart(hw_pass ? "PASS" : "FAIL");
	print_uart(" ");
	print_uart(sw_pass == hw_pass ? "[MATCH]\n" : "[MISMATCH]\n");

	return sw_pass != hw_pass;
}

/* Exact-boundary case: construct s1/s2 so the true sum is a known value,
 * then check bound==sum (must PASS, inclusive <=) and bound==sum-1 (must
 * FAIL) both match between SW and HW. */
static int
run_boundary_case(void)
{
	unsigned i;
	uint32_t true_sum;
	int failures = 0;
	int sw_pass, hw_pass;

	memset(s1_buf, 0, sizeof s1_buf);
	memset(s2_buf, 0, sizeof s2_buf);
	for (i = 0; i < 8; i++) {
		s1_buf[i] = (int16_t)(100 + i);
		s2_buf[i] = (int16_t)(50 + i);
	}
	true_sum = 0;
	for (i = 0; i < 8; i++) {
		int32_t z1 = s1_buf[i], z2 = s2_buf[i];
		true_sum += (uint32_t)(z1 * z1) + (uint32_t)(z2 * z2);
	}

	sw_pass = sw_is_short(s1_buf, s2_buf, N, true_sum);
	hw_pass = hw_is_short(s1_buf, s2_buf, N, true_sum);
	print_uart("boundary[bound=sum]: sw=");
	print_uart(sw_pass ? "PASS" : "FAIL");
	print_uart(" hw=");
	print_uart(hw_pass ? "PASS" : "FAIL");
	print_uart(" ");
	print_uart((sw_pass == hw_pass) && sw_pass ? "[MATCH]\n" : "[MISMATCH]\n");
	if (sw_pass != hw_pass || !sw_pass) failures++;

	sw_pass = sw_is_short(s1_buf, s2_buf, N, true_sum - 1);
	hw_pass = hw_is_short(s1_buf, s2_buf, N, true_sum - 1);
	print_uart("boundary[bound=sum-1]: sw=");
	print_uart(sw_pass ? "PASS" : "FAIL");
	print_uart(" hw=");
	print_uart(hw_pass ? "PASS" : "FAIL");
	print_uart(" ");
	print_uart((sw_pass == hw_pass) && !sw_pass ? "[MATCH]\n" : "[MISMATCH]\n");
	if (sw_pass != hw_pass || sw_pass) failures++;

	return failures;
}

/* Accumulator-overflow case: full-range int16_t magnitudes over all N
 * coefficients push the running sum past 2^31-1, forcing the sticky
 * saturation path (`ng |= s` .. `s |= -(ng>>31)`) in both SW and HW. */
static int
run_overflow_case(void)
{
	uint32_t rng = 0xDEADBEEFu;
	int sw_pass, hw_pass;

	fill_random(s1_buf, N, &rng, 32000);
	fill_random(s2_buf, N, &rng, 32000);

	/* bound is irrelevant to whether saturation triggers, but use a
	 * generous one so a PASS here would only happen if HW's saturated
	 * sum happens to equal SW's (both 0xFFFFFFFF) -- i.e. any mismatch
	 * in the sticky-overflow logic shows up as a MISMATCH below. */
	sw_pass = sw_is_short(s1_buf, s2_buf, N, 0x7FFFFFFFu);
	hw_pass = hw_is_short(s1_buf, s2_buf, N, 0x7FFFFFFFu);

	print_uart("overflow-saturate: sw=");
	print_uart(sw_pass ? "PASS" : "FAIL");
	print_uart(" hw=");
	print_uart(hw_pass ? "PASS" : "FAIL");
	print_uart(" ");
	print_uart((sw_pass == hw_pass) && !sw_pass ? "[MATCH]\n" : "[MISMATCH]\n");

	return (sw_pass != hw_pass) || sw_pass;
}

static int
run_n_zero_case(void)
{
	int sw_pass, hw_pass;

	sw_pass = sw_is_short(s1_buf, s2_buf, 0, 0);
	hw_pass = hw_is_short(s1_buf, s2_buf, 0, 0);

	print_uart("n=0: sw=");
	print_uart(sw_pass ? "PASS" : "FAIL");
	print_uart(" hw=");
	print_uart(hw_pass ? "PASS" : "FAIL");
	print_uart(" ");
	print_uart((sw_pass == hw_pass) && sw_pass ? "[MATCH]\n" : "[MISMATCH]\n");

	return (sw_pass != hw_pass) || !sw_pass;
}

int
main(void)
{
	int failures = 0;
	uint32_t cycles;

	clear_csr(mcountinhibit, 1);

	print_uart("=== falcon-normcheck: Zf(is_short)() SW-vs-HW ===\n");

	write_csr(mcycle, 0);
	failures += run_random_case();
	failures += run_boundary_case();
	failures += run_overflow_case();
	failures += run_n_zero_case();
	cycles = (uint32_t)read_csr(mcycle);

	print_uart("Total cycles: ");
	print_uart_dec((int)cycles);
	print_uart("\n");

	if (failures == 0) {
		print_uart("FINAL STATUS: ALL TESTS PASSED\n");
	} else {
		print_uart("FINAL STATUS: ");
		print_uart_dec(failures);
		print_uart(" TEST(S) FAILED\n");
	}

	return failures;
}