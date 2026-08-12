/*
 * tests/app-tests/falcon-decompress/main.c
 *
 * Standalone SW-vs-HW test for falcon_decode.sv (Zf(comp_decode)() offload,
 * vrf_ip/rtl/falcon_decode.sv). Independent, from-scratch software
 * encoder/decoder pair (sw_comp_encode/sw_comp_decode below), mirroring
 * Falcon's own Zf(comp_encode)()/Zf(comp_decode)() (codec.c) bit-for-bit
 * per the reference's documented format -- 1 sign bit + 7 low magnitude
 * bits + unary-coded high bits -- not copy-pasted from that file, so a
 * hardware bug and a "copied the same mistake" software bug can't both
 * produce a false PASS.
 *
 * Covers: a realistic random coefficient set (magnitudes distributed like
 * real Falcon-512 signature coefficients), the two magnitude boundary
 * cases (0 and 2047, both signs), and three malformed-input cases
 * (truncated stream, forced unary-run overflow, corrupted trailing bits)
 * to confirm DECODE_CTRL.FAIL triggers at the same conditions
 * Zf(comp_decode)()'s `return 0` does.
 */

#include <stdint.h>
#include <string.h>

#include "encoding.h"
#include "vrf_axi.h"
#include "uart.h"

#define VRF_AXI_BASE_ADDR 0x50000000UL

/* Non-cacheable DRAM scratch window for the decoder's output, same
 * convention/rationale as vrfy.c's VRF_NTT_HW_SCRATCH_ADDR/common.c's
 * VRF_REJ_HW_SCRATCH_ADDR: this SoC's DcacheFlushOnFence/
 * DcacheInvalidateOnFlush are both 0, so an accelerator DMA-writing
 * straight into ordinary cacheable memory can leave a stale D$ line
 * masking the write (confirmed on real RTL by this test during bring-up:
 * every decoded value read back as the CPU's own pre-initialization value,
 * the fingerprint of a stale-cache-hit, not a hardware decode bug -- the
 * *input* side needs no equivalent treatment, since a plain `fence`
 * already correctly orders CPU writes into encoded[] ahead of the
 * accelerator's own read, the same as every other job's absorb input on
 * this accelerator). Decode into this scratch window, then copy out via
 * an ordinary software loop -- exactly how Zf(hash_to_point_hw)() (Falcon
 * shake.c) already handles its own HW-written output.
 */
#define VRF_DECODE_HW_SCRATCH_ADDR 0x80F0B000UL

#define N 512
#define MAXBUF 1200  /* generous upper bound for N=512's worst-case encoding */

/* ===================================================================== */
/* SW reference: encoder + decoder, independently derived from the       */
/* documented format (1 sign + 7 low bits + unary high bits).            */
/* ===================================================================== */

static size_t
sw_comp_encode(uint8_t *out, size_t max_out_len, const int16_t *x, unsigned n)
{
	uint32_t acc = 0;
	unsigned acc_len = 0;
	size_t v = 0;
	unsigned u;

	for (u = 0; u < n; u++) {
		if (x[u] < -2047 || x[u] > 2047) {
			return 0;
		}
	}

	for (u = 0; u < n; u++) {
		int t = x[u];
		unsigned w, sign = 0;

		if (t < 0) {
			t = -t;
			sign = 1;
		}
		w = (unsigned)t;

		acc = (acc << 1) | sign;
		acc = (acc << 7) | (w & 127u);
		acc_len += 8;
		w >>= 7;

		/* w <= 15 here (|x[u]| <= 2047), so at most 16 more bits. */
		acc = (acc << (w + 1)) | 1u;
		acc_len += w + 1;

		while (acc_len >= 8) {
			acc_len -= 8;
			if (v >= max_out_len) {
				return 0;
			}
			out[v++] = (uint8_t)(acc >> acc_len);
		}
	}

	if (acc_len > 0) {
		if (v >= max_out_len) {
			return 0;
		}
		out[v++] = (uint8_t)(acc << (8 - acc_len));
	}

	return v;
}

static size_t
sw_comp_decode(int16_t *x, unsigned n, const uint8_t *in, size_t max_in_len)
{
	uint32_t acc = 0;
	unsigned acc_len = 0;
	size_t v = 0;
	unsigned u;

	for (u = 0; u < n; u++) {
		unsigned b, s, m;

		if (v >= max_in_len) {
			return 0;
		}
		acc = (acc << 8) | (uint32_t)in[v++];
		b = acc >> acc_len;
		s = b & 128;
		m = b & 127;

		for (;;) {
			if (acc_len == 0) {
				if (v >= max_in_len) {
					return 0;
				}
				acc = (acc << 8) | (uint32_t)in[v++];
				acc_len = 8;
			}
			acc_len--;
			if (((acc >> acc_len) & 1) != 0) {
				break;
			}
			m += 128;
			if (m > 2047) {
				return 0;
			}
		}

		if (s && m == 0) {
			return 0;
		}

		x[u] = (int16_t)(s ? -(int)m : (int)m);
	}

	if ((acc & ((1u << acc_len) - 1u)) != 0) {
		return 0;
	}

	return v;
}

/* ===================================================================== */
/* HW dispatch                                                            */
/* ===================================================================== */

static int
hw_comp_decode(int16_t *x, unsigned n, const uint8_t *in, size_t max_in_len,
    uint32_t *v_out)
{
	uint64_t volatile *decode_in_addr = (uint64_t volatile *)
	    (VRF_AXI_BASE_ADDR + VRF_DECODE_IN_ADDR_REG_OFFSET);
	uint64_t volatile *decode_out_addr = (uint64_t volatile *)
	    (VRF_AXI_BASE_ADDR + VRF_DECODE_OUT_ADDR_REG_OFFSET);
	uint64_t volatile *decode_params = (uint64_t volatile *)
	    (VRF_AXI_BASE_ADDR + VRF_DECODE_PARAMS_REG_OFFSET);
	uint64_t volatile *decode_ctrl = (uint64_t volatile *)
	    (VRF_AXI_BASE_ADDR + VRF_DECODE_CTRL_REG_OFFSET);
	int16_t volatile *scratch = (int16_t volatile *)VRF_DECODE_HW_SCRATCH_ADDR;
	uint64_t ctrl_val;
	int fail;
	unsigned i;

	__asm__ volatile ("fence" ::: "memory");

	*decode_in_addr  = (uint64_t)(uintptr_t)in;
	*decode_out_addr = (uint64_t)VRF_DECODE_HW_SCRATCH_ADDR;
	*decode_params = ((uint64_t)max_in_len << VRF_DECODE_PARAMS_MAX_LEN_OFFSET)
	    | ((uint64_t)n << VRF_DECODE_PARAMS_N_OFFSET);

	*decode_ctrl = (uint64_t)1 << VRF_DECODE_CTRL_GO_BIT;
	while (((*decode_ctrl) & ((uint64_t)1 << VRF_DECODE_CTRL_DONE_BIT)) == 0);

	ctrl_val = *decode_ctrl;
	fail = (ctrl_val & ((uint64_t)1 << VRF_DECODE_CTRL_FAIL_BIT)) != 0;
	*v_out = (uint32_t)((ctrl_val >> VRF_DECODE_CTRL_V_OFFSET) & VRF_DECODE_CTRL_V_MASK);

	*decode_ctrl = 0;

	__asm__ volatile ("fence" ::: "memory");

	if (!fail) {
		for (i = 0; i < n; i++) {
			x[i] = scratch[i];
		}
	}

	return fail;
}

/* ===================================================================== */
/* Test driver                                                            */
/* ===================================================================== */

static int16_t coeffs_orig[N];
static int16_t coeffs_sw[N];
static int16_t coeffs_hw[N];
static uint8_t encoded[MAXBUF];

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

static int
run_happy_path(const char *label, uint32_t seed_state)
{
	uint32_t rng = seed_state;
	size_t enc_len, sw_len;
	uint32_t hw_v;
	int hw_fail;
	unsigned i;
	int mismatches = 0;

	for (i = 0; i < N; i++) {
		/* magnitudes distributed like real Falcon-512 signature
		 * coefficients: mostly small, occasionally larger, matching
		 * common.c's own stated max(f,g)~32/std~5.6 style profile
		 * loosely (exact distribution doesn't matter for this test,
		 * only that encode/decode round-trip correctly). */
		int32_t mag = (int32_t)(xorshift32(&rng) % 200);
		int sign = xorshift32(&rng) & 1;
		coeffs_orig[i] = (int16_t)(sign ? -mag : mag);
	}

	print_uart(label);
	print_uart(" post-gen: ");
	for (i = 0; i < 5; i++) {
		print_uart_dec(coeffs_orig[i]);
		print_uart(" ");
	}
	print_uart("\n");

	enc_len = sw_comp_encode(encoded, MAXBUF, coeffs_orig, N);
	if (enc_len == 0) {
		print_uart(label);
		print_uart(": ENCODE FAILED\n");
		return 1;
	}

	sw_len = sw_comp_decode(coeffs_sw, N, encoded, enc_len);
	hw_fail = hw_comp_decode(coeffs_hw, N, encoded, enc_len, &hw_v);

	if (sw_len == 0 || hw_fail || hw_v != sw_len) {
		print_uart(label);
		print_uart(": unexpected FAIL (sw_len=");
		print_uart_dec((int)sw_len);
		print_uart(" hw_fail=");
		print_uart_dec(hw_fail);
		print_uart(" hw_v=");
		print_uart_dec((int)hw_v);
		print_uart(")\n");
		return 1;
	}

	{
		int first_reported = 0;
		for (i = 0; i < N; i++) {
			if (coeffs_sw[i] != coeffs_orig[i] || coeffs_hw[i] != coeffs_orig[i]) {
				mismatches++;
				if (first_reported < 5) {
					first_reported++;
					print_uart("  mismatch idx=");
					print_uart_dec((int)i);
					print_uart(" orig=");
					print_uart_dec(coeffs_orig[i]);
					print_uart(" sw=");
					print_uart_dec(coeffs_sw[i]);
					print_uart(" hw=");
					print_uart_dec(coeffs_hw[i]);
					print_uart("\n");
				}
			}
		}
	}

	print_uart(label);
	print_uart(": ");
	print_uart(mismatches == 0 ? "[PASS]" : "[FAIL]");
	print_uart(" mismatches=");
	print_uart_dec(mismatches);
	print_uart(" bytes=");
	print_uart_dec((int)enc_len);
	print_uart("\n");

	return mismatches != 0;
}

static int
run_boundary_case(void)
{
	unsigned i;
	size_t enc_len, sw_len;
	uint32_t hw_v;
	int hw_fail;
	int mismatches = 0;

	for (i = 0; i < N; i++) {
		if (i % 4 == 0) coeffs_orig[i] = 0;
		else if (i % 4 == 1) coeffs_orig[i] = 2047;
		else if (i % 4 == 2) coeffs_orig[i] = -2047;
		else coeffs_orig[i] = 1;
	}

	enc_len = sw_comp_encode(encoded, MAXBUF, coeffs_orig, N);
	sw_len = sw_comp_decode(coeffs_sw, N, encoded, enc_len);
	hw_fail = hw_comp_decode(coeffs_hw, N, encoded, enc_len, &hw_v);

	if (enc_len == 0 || sw_len == 0 || hw_fail || hw_v != sw_len) {
		print_uart("boundary: unexpected FAIL\n");
		return 1;
	}

	{
		int first_reported = 0;
		for (i = 0; i < N; i++) {
			if (coeffs_sw[i] != coeffs_orig[i] || coeffs_hw[i] != coeffs_orig[i]) {
				mismatches++;
				if (first_reported < 5) {
					first_reported++;
					print_uart("  mismatch idx=");
					print_uart_dec((int)i);
					print_uart(" orig=");
					print_uart_dec(coeffs_orig[i]);
					print_uart(" sw=");
					print_uart_dec(coeffs_sw[i]);
					print_uart(" hw=");
					print_uart_dec(coeffs_hw[i]);
					print_uart("\n");
				}
			}
		}
	}

	print_uart("boundary (0/+-2047): ");
	print_uart(mismatches == 0 ? "[PASS]\n" : "[FAIL]\n");
	return mismatches != 0;
}

static int
run_malformed_cases(void)
{
	size_t enc_len, sw_len;
	uint32_t hw_v;
	int hw_fail;
	int failures = 0;
	unsigned i;

	for (i = 0; i < N; i++) {
		coeffs_orig[i] = (int16_t)((i * 37) % 100);
	}
	enc_len = sw_comp_encode(encoded, MAXBUF, coeffs_orig, N);

	/* Case 1: truncated stream (max_in_len cut well short). */
	sw_len = sw_comp_decode(coeffs_sw, N, encoded, enc_len / 4);
	hw_fail = hw_comp_decode(coeffs_hw, N, encoded, enc_len / 4, &hw_v);
	print_uart("malformed[truncated]: sw=");
	print_uart(sw_len == 0 ? "FAIL" : "PASS");
	print_uart(" hw=");
	print_uart(hw_fail ? "FAIL" : "PASS");
	print_uart(" ");
	print_uart((sw_len == 0) == (hw_fail != 0) ? "[MATCH]\n" : "[MISMATCH]\n");
	if ((sw_len == 0) != (hw_fail != 0)) failures++;

	/* Case 2: force a long run of continuation-bits (0-bits) into the
	 * first coefficient's unary tail by zeroing bytes right after its
	 * sign+magnitude byte, without ever supplying a terminating 1 bit
	 * within max_in_len -- forces "stream exhausted mid-coefficient",
	 * a related but distinct rejection path from case 1. */
	{
		uint8_t corrupt[MAXBUF];
		memcpy(corrupt, encoded, enc_len);
		for (i = 1; i < enc_len; i++) {
			corrupt[i] = 0x00;
		}
		sw_len = sw_comp_decode(coeffs_sw, N, corrupt, enc_len);
		hw_fail = hw_comp_decode(coeffs_hw, N, corrupt, enc_len, &hw_v);
		print_uart("malformed[unary-exhaust]: sw=");
		print_uart(sw_len == 0 ? "FAIL" : "PASS");
		print_uart(" hw=");
		print_uart(hw_fail ? "FAIL" : "PASS");
		print_uart(" ");
		print_uart((sw_len == 0) == (hw_fail != 0) ? "[MATCH]\n" : "[MISMATCH]\n");
		if ((sw_len == 0) != (hw_fail != 0)) failures++;
	}

	/* Case 3: trailing-bits-must-be-zero violation -- flip a low bit in
	 * the final byte of an otherwise-valid full-length encoding. */
	{
		uint8_t corrupt[MAXBUF];
		memcpy(corrupt, encoded, enc_len);
		corrupt[enc_len - 1] |= 0x01;
		sw_len = sw_comp_decode(coeffs_sw, N, corrupt, enc_len);
		hw_fail = hw_comp_decode(coeffs_hw, N, corrupt, enc_len, &hw_v);
		print_uart("malformed[trailing-bits]: sw=");
		print_uart(sw_len == 0 ? "FAIL" : "PASS");
		print_uart(" hw=");
		print_uart(hw_fail ? "FAIL" : "PASS");
		print_uart(" ");
		print_uart((sw_len == 0) == (hw_fail != 0) ? "[MATCH]\n" : "[MISMATCH]\n");
		if ((sw_len == 0) != (hw_fail != 0)) failures++;
	}

	return failures;
}

/* Minimal repro: two single-coefficient decodes back to back, with
 * distinct values, to isolate whether HW state carries over incorrectly
 * between separate job dispatches to the SAME peripheral. */
static int
run_minimal_repro(void)
{
	uint8_t enc1[4], enc2[4];
	int16_t one[1];
	size_t len1, len2;
	uint32_t v1, v2;
	int f1, f2;
	int16_t val1 = 5;
	int16_t val2 = -77;
	int failures = 0;

	len1 = sw_comp_encode(enc1, sizeof enc1, &val1, 1);
	len2 = sw_comp_encode(enc2, sizeof enc2, &val2, 1);

	one[0] = 0;
	f1 = hw_comp_decode(one, 1, enc1, len1, &v1);
	print_uart("repro call1: enc_len=");
	print_uart_dec((int)len1);
	print_uart(" fail=");
	print_uart_dec(f1);
	print_uart(" v=");
	print_uart_dec((int)v1);
	print_uart(" decoded=");
	print_uart_dec(one[0]);
	print_uart(" expect=");
	print_uart_dec(val1);
	print_uart("\n");
	if (f1 || v1 != len1 || one[0] != val1) failures++;

	one[0] = 0;
	f2 = hw_comp_decode(one, 1, enc2, len2, &v2);
	print_uart("repro call2: enc_len=");
	print_uart_dec((int)len2);
	print_uart(" fail=");
	print_uart_dec(f2);
	print_uart(" v=");
	print_uart_dec((int)v2);
	print_uart(" decoded=");
	print_uart_dec(one[0]);
	print_uart(" expect=");
	print_uart_dec(val2);
	print_uart("\n");
	if (f2 || v2 != len2 || one[0] != val2) failures++;

	print_uart("minimal-repro: ");
	print_uart(failures == 0 ? "[PASS]\n" : "[FAIL]\n");
	return failures;
}

int
main(void)
{
	int failures = 0;
	uint32_t cycles;

	clear_csr(mcountinhibit, 1);

	print_uart("=== falcon-decompress: Zf(comp_decode)() SW-vs-HW ===\n");

	write_csr(mcycle, 0);
	failures += run_minimal_repro();
	failures += run_happy_path("random-512", 0xC0FFEEu);
	failures += run_happy_path("random-512-b", 0x1234ABu);
	failures += run_boundary_case();
	failures += run_malformed_cases();
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