/*
 * Standalone correctness/speedup test for ntt_engine.sv's Revision 3
 * addition: hardware vect_FFT()/vect_iFFT() (ng_fxp.c), the fixed-point
 * transform behind solve_NTRU_intermediate()'s babai_loop (see
 * NTT_ACCEL_DESIGN.md's "Fixed-point FFT scoping" section for the
 * derivation this validates). This test is scoped to vect_FFT/vect_iFFT
 * in isolation -- NOT the whole babai_loop (poly_sub_scaled and friends
 * stay software-only, out of scope here) -- matching how ntt_engine_test.c
 * validates mp_NTT/mp_iNTT in isolation before any solve_NTRU() wiring.
 *
 * Software reference: the REAL vect_FFT()/vect_iFFT() from ng_fxp.c, not
 * a hand transliteration -- same "link and call directly" approach as
 * ntt_engine_test.c's mp_NTT_sw()/mp_iNTT_sw() calls. Correctness is a
 * bit-exact compare of every fxr .v word (both sides compute the same
 * fixed-point arithmetic on the same GM_TAB values -- fft_gm_rom.sv is a
 * verbatim extraction of ng_fxp.c's GM_TAB, not a re-derivation).
 *
 * Same non-cacheable DRAM scratch-window treatment as ntt_engine_test.c
 * (see that file's header comment) -- ntt_engine writes results back as
 * a second AXI master, so every buffer it touches must live in the PMA's
 * uncached window.
 */

#include <stddef.h>
#include <stdint.h>
#include <string.h>

#include "uart.h"
#include "ng_inner.h"
#include "keccak_axi.h"
#include "encoding.h"

/* true software references (ng_fxp.c), external linkage, not declared in
 * ng_inner.h (only the vect_FFT()/vect_iFFT() dispatchers are) -- called
 * directly here to bypass those dispatchers, which now redirect to
 * hardware for logn >= FFT_HW_MIN_LOGN. */
void vect_FFT_sw(unsigned logn, fxr *f);
void vect_iFFT_sw(unsigned logn, fxr *f);

#define KECCAK_AXI_BASE_ADDR 0x50000000UL
#define FFT_HW_SCRATCH_ADDR  0x80F10000UL /* separate from ntt_engine_test.c's 0x80F00000 window and ng_fxp.c's own 0x80F01000 production window */

#define MAX_LOGN 8u
#define MAX_N    (1u << MAX_LOGN)

/* job_mode_i encoding (see ntt_engine.sv header comment): bit2=FFT family,
 * bit0=direction. 3'b100 = vect_FFT, 3'b101 = vect_iFFT. */
#define MODE_FFT   4u
#define MODE_IFFT  5u

static fxr volatile *const hw_a =
    (fxr volatile *)(FFT_HW_SCRATCH_ADDR + 0x000);

static fxr sw_ref[MAX_N];
static fxr hw_in[MAX_N];

static void
hw_fft_run(uint64_t a_addr, unsigned logn, unsigned mode)
{
	uint64_t volatile *ntt_a_addr = (uint64_t volatile *)
	    (KECCAK_AXI_BASE_ADDR + KECCAK_NTT_A_ADDR_REG_OFFSET);
	uint64_t volatile *ntt_logn = (uint64_t volatile *)
	    (KECCAK_AXI_BASE_ADDR + KECCAK_NTT_LOGN_REG_OFFSET);
	uint64_t volatile *ntt_ctrl = (uint64_t volatile *)
	    (KECCAK_AXI_BASE_ADDR + KECCAK_NTT_CTRL_REG_OFFSET);

	/* engine's own job_logn_i = (real FFT logn) - 1 -- same trick as
	   autoadj, see ntt_engine.sv's header comment's Revision 3 section. */
	*ntt_a_addr = a_addr;
	*ntt_logn   = logn - 1;

	*ntt_ctrl = ((uint64_t)1 << KECCAK_NTT_CTRL_GO_BIT)
	    | ((uint64_t)mode << KECCAK_NTT_CTRL_MODE_OFFSET);
	while (((*ntt_ctrl) & ((uint64_t)1 << KECCAK_NTT_CTRL_DONE_BIT)) == 0);

	*ntt_ctrl = 0;
}

/* deterministic pseudo-random small integers, converted to fxr via the
   real vect_set() -- keeps magnitudes small (int8 range) so intermediate
   fxc_add/fxc_sub sums can't approach 64-bit overflow, matching the
   "correctness test, not a numerical-range test" scope. */
static void
fill_input(unsigned logn, unsigned seed)
{
	unsigned n = 1u << logn;
	int8_t tmp[MAX_N];
	for (unsigned i = 0; i < n; i++) {
		tmp[i] = (int8_t)((i * 41u + seed * 17u + 3u) & 0x7Fu) - 64;
	}
	vect_set(logn, sw_ref, tmp);
	memcpy(hw_in, sw_ref, n * sizeof(fxr));
}

static int
run_case(const char *name, unsigned logn, unsigned mode)
{
	unsigned n = 1u << logn;
	int errors = 0;

	fill_input(logn, mode);

	if (mode == MODE_FFT) {
		vect_FFT_sw(logn, sw_ref);
	} else {
		vect_iFFT_sw(logn, sw_ref);
	}

	for (unsigned i = 0; i < n; i++) {
		hw_a[i].v = hw_in[i].v;
	}

	hw_fft_run((uint64_t)(uintptr_t)hw_a, logn, mode);

	for (unsigned i = 0; i < n; i++) {
		uint64_t got = hw_a[i].v;
		uint64_t want = sw_ref[i].v;
		if (got != want) {
			errors++;
			if (errors <= 4) {
				print_uart("  ");
				print_uart(name);
				print_uart(" a[");
				print_uart_dec((int)i);
				print_uart("] mismatch: sw=");
				print_uart_addr(want);
				print_uart(" hw=");
				print_uart_addr(got);
				print_uart("\n");
			}
		}
	}

	print_uart("  ");
	print_uart(name);
	print_uart(" (logn=");
	print_uart_dec((int)logn);
	print_uart("): ");
	print_uart(errors == 0 ? "OK" : "MISMATCH");
	print_uart(" (");
	print_uart_dec(errors);
	print_uart(" mismatches)\n");

	return errors;
}

/* single-operation cycle-count benchmark, mirroring ntt_sw_bench.c /
   ntt_hw_bench.c's pattern -- separate from the correctness check above
   so mcycle isn't polluted by the compare loop or UART prints. */
static void
bench_case(const char *name, unsigned logn, unsigned mode)
{
	unsigned int sw_cycles, hw_cycles;

	fill_input(logn, 99);

	clear_csr(mcountinhibit, 1);
	write_csr(mcycle, 0);
	if (mode == MODE_FFT) {
		vect_FFT_sw(logn, sw_ref);
	} else {
		vect_iFFT_sw(logn, sw_ref);
	}
	sw_cycles = (unsigned int)read_csr(mcycle);

	for (unsigned i = 0; i < (1u << logn); i++) {
		hw_a[i].v = hw_in[i].v;
	}
	write_csr(mcycle, 0);
	hw_fft_run((uint64_t)(uintptr_t)hw_a, logn, mode);
	hw_cycles = (unsigned int)read_csr(mcycle);

	print_uart("  ");
	print_uart(name);
	print_uart(" (logn=");
	print_uart_dec((int)logn);
	print_uart("): sw=");
	print_uart_dec((int)sw_cycles);
	print_uart(" hw=");
	print_uart_dec((int)hw_cycles);
	print_uart(" cycles, speedup=");
	if (hw_cycles > 0) {
		print_uart_dec((int)(sw_cycles * 100u / hw_cycles / 100u));
		print_uart(".");
		print_uart_dec((int)((sw_cycles * 100u / hw_cycles) % 100u));
	} else {
		print_uart("inf");
	}
	print_uart("x\n");
}

int
main(void)
{
	int errors = 0;
	unsigned logns[] = { 3u, 8u };

	print_uart("FFT/iFFT hardware engine test (ntt_engine.sv Revision 3)\n");

	print_uart("-- correctness --\n");
	for (unsigned li = 0; li < sizeof(logns) / sizeof(logns[0]); li++) {
		errors += run_case("FFT ", logns[li], MODE_FFT);
		errors += run_case("iFFT", logns[li], MODE_IFFT);
	}

	print_uart("-- single-operation benchmark --\n");
	for (unsigned li = 0; li < sizeof(logns) / sizeof(logns[0]); li++) {
		bench_case("FFT ", logns[li], MODE_FFT);
		bench_case("iFFT", logns[li], MODE_IFFT);
	}

	if (errors == 0) {
		print_uart("FFT engine test: ALL OK\n");
	} else {
		print_uart("FFT engine test: FAILED, total mismatches=");
		print_uart_dec(errors);
		print_uart("\n");
	}

	return errors == 0 ? 0 : 1;
}
