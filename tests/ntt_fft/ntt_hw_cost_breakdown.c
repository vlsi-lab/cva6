/*
 * Measures the cycle cost of a single ntt_engine.sv forward-NTT call in
 * isolation, split into sub-phases -- mirrors
 * tests/keccak64/keccak_single_call_cost.c exactly (full round trip /
 * upload / start+poll / readback), applied to mp_NTT_hw()'s own internal
 * sequence (ng_mp31.c) instead of Keccak's CSREG permute, to separate
 * "fixed per-call overhead" (scratch-window copy in/out, register
 * writes) from "actual hardware compute+handshake time" (GO+poll) and
 * decide where further optimization effort is best spent.
 *
 * n=256, p=P1: same case as ntt_sw_bench.c/ntt_hw_bench.c. This file
 * pokes registers directly (not via mp_NTT_hw()) so each phase can be
 * cycle-reset independently; no correctness check here (that's already
 * covered by ntt_engine_test.c and the other two benchmarks) -- this
 * file exists purely to attribute cycles to phases.
 *
 * Only `a[]` is staged through the non-cacheable scratch window (same
 * reasoning as mp_NTT_hw()): the D$ here is write-through, so the CPU's
 * writes to gm[] during setup are already visible in DRAM by the time
 * hardware reads them -- the coherency hazard only exists for the
 * hardware's writes back to `a[]`, which the CPU reads afterward.
 */

#include <stddef.h>
#include <stdint.h>
#include <string.h>

#include "uart.h"
#include "encoding.h"
#include "ng_inner.h"
#include "keccak_axi.h"

#define KECCAK_AXI_BASE_ADDR 0x50000000UL
#define NTT_HW_SCRATCH_ADDR  0x80F00A00UL   /* distinct from ng_mp31.c's/hawk_vrfy.c's windows */
#define N     256u
#define LOGN  8u

static uint32_t gm[N], igm[N];
static uint32_t a_in[N];

int
main(void)
{
	uint32_t p   = PRIMES[0].p;
	uint32_t p0i = PRIMES[0].p0i;
	uint32_t volatile *scratch = (uint32_t volatile *)NTT_HW_SCRATCH_ADDR;

	uint64_t volatile *ntt_a_addr = (uint64_t volatile *)
	    (KECCAK_AXI_BASE_ADDR + KECCAK_NTT_A_ADDR_REG_OFFSET);
	uint64_t volatile *ntt_gm_addr = (uint64_t volatile *)
	    (KECCAK_AXI_BASE_ADDR + KECCAK_NTT_GM_ADDR_REG_OFFSET);
	uint64_t volatile *ntt_logn = (uint64_t volatile *)
	    (KECCAK_AXI_BASE_ADDR + KECCAK_NTT_LOGN_REG_OFFSET);
	uint64_t volatile *ntt_p_val = (uint64_t volatile *)
	    (KECCAK_AXI_BASE_ADDR + KECCAK_NTT_P_VAL_REG_OFFSET);
	uint64_t volatile *ntt_p0i_val = (uint64_t volatile *)
	    (KECCAK_AXI_BASE_ADDR + KECCAK_NTT_P0I_VAL_REG_OFFSET);
	uint64_t volatile *ntt_ctrl = (uint64_t volatile *)
	    (KECCAK_AXI_BASE_ADDR + KECCAK_NTT_CTRL_REG_OFFSET);

	int cycles_full, cycles_upload, cycles_startpoll, cycles_readback;
	unsigned i;

	mp_mkgmigm(LOGN, gm, igm, PRIMES[0].g, PRIMES[0].ig, p, p0i);
	for (i = 0; i < N; i++) {
		a_in[i] = (i * 2654435761u + 12345u) % p;
	}

	printf("Single mp_NTT hardware call cost breakdown (n=%u, P1):\n", N);

	clear_csr(mcountinhibit, 1);

	/* full round trip: scratch-copy-in + regs/GO + poll + scratch-copy-out */
	write_csr(mcycle, 0);
	for (i = 0; i < N; i++) scratch[i] = a_in[i];
	*ntt_a_addr   = (uint64_t)NTT_HW_SCRATCH_ADDR;
	*ntt_gm_addr  = (uint64_t)(uintptr_t)gm;
	*ntt_logn     = LOGN;
	*ntt_p_val    = p;
	*ntt_p0i_val  = p0i;
	*ntt_ctrl     = (uint64_t)1 << KECCAK_NTT_CTRL_GO_BIT;
	while (((*ntt_ctrl) & ((uint64_t)1 << KECCAK_NTT_CTRL_DONE_BIT)) == 0);
	*ntt_ctrl = 0;
	for (i = 0; i < N; i++) a_in[i] = scratch[i];
	cycles_full = read_csr(mcycle);

	/* scratch-copy-in only (N stores to the uncached window) */
	write_csr(mcycle, 0);
	for (i = 0; i < N; i++) scratch[i] = a_in[i];
	cycles_upload = read_csr(mcycle);

	/* register writes + GO + poll only (actual hardware compute+handshake) */
	write_csr(mcycle, 0);
	*ntt_a_addr   = (uint64_t)NTT_HW_SCRATCH_ADDR;
	*ntt_gm_addr  = (uint64_t)(uintptr_t)gm;
	*ntt_logn     = LOGN;
	*ntt_p_val    = p;
	*ntt_p0i_val  = p0i;
	*ntt_ctrl     = (uint64_t)1 << KECCAK_NTT_CTRL_GO_BIT;
	while (((*ntt_ctrl) & ((uint64_t)1 << KECCAK_NTT_CTRL_DONE_BIT)) == 0);
	cycles_startpoll = read_csr(mcycle);
	*ntt_ctrl = 0;

	/* scratch-copy-out only (N loads from the uncached window) */
	write_csr(mcycle, 0);
	for (i = 0; i < N; i++) a_in[i] = scratch[i];
	cycles_readback = read_csr(mcycle);

	printf("  full round trip (upload+regs/GO+poll+readback): %d cycles\n", cycles_full);
	printf("  scratch-copy-in  (%u stores):                    %d cycles\n", N, cycles_upload);
	printf("  regs+GO+poll (hardware compute+handshake):       %d cycles\n", cycles_startpoll);
	printf("  scratch-copy-out (%u loads):                     %d cycles\n", N, cycles_readback);

	return 0;
}
