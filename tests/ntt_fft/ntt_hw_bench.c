/*
 * Pure-hardware single-operation benchmark for mp_NTT()/mp_iNTT(),
 * mirroring tests/keccak64/keccak_axi.c: measures the isolated wall-clock
 * cost of one forward and one inverse transform run entirely through
 * ntt_engine.sv, via mp_NTT_hw() (ng_mp31.c, exposed with external
 * linkage specifically for this) -- register pokes, DONE poll, and the
 * non-cacheable-scratch-window copy in/out all included, since that is
 * exactly what a real caller (ng_hawk.c, ng_ntru.c, hawk_vrfy.c) pays per
 * call. See ntt_hw_cost_breakdown.c for a split of those sub-costs.
 *
 * Same n=256/P1 case and same round-trip correctness check as
 * ntt_sw_bench.c, so the two cycle counts are directly comparable.
 */

#include <stddef.h>
#include <stdint.h>
#include <string.h>

#include "uart.h"
#include "encoding.h"
#include "ng_inner.h"

#define N     256u
#define LOGN  8u

void mp_NTT_hw(unsigned logn, uint32_t *restrict a,
    const uint32_t *restrict gm, uint32_t p, uint32_t p0i, unsigned mode);

static uint32_t a_orig[N], a_work[N], gm[N], igm[N];

int
main(void)
{
	uint32_t p   = PRIMES[0].p;
	uint32_t p0i = PRIMES[0].p0i;
	int cycles_ntt, cycles_intt;
	int errors = 0;

	/* untimed setup: twiddle tables + deterministic input */
	mp_mkgmigm(LOGN, gm, igm, PRIMES[0].g, PRIMES[0].ig, p, p0i);
	for (unsigned i = 0; i < N; i++) {
		a_orig[i] = (i * 2654435761u + 12345u) % p;
	}
	memcpy(a_work, a_orig, sizeof a_orig);

	printf("mp_NTT/mp_iNTT pure-hardware single-operation benchmark (n=%u, P1)\n", N);

	clear_csr(mcountinhibit, 1);

	write_csr(mcycle, 0);
	mp_NTT_hw(LOGN, a_work, gm, p, p0i, 0);
	cycles_ntt = read_csr(mcycle);

	write_csr(mcycle, 0);
	mp_NTT_hw(LOGN, a_work, igm, p, p0i, 1);
	cycles_intt = read_csr(mcycle);

	for (unsigned i = 0; i < N; i++) {
		if (a_work[i] != a_orig[i]) {
			errors++;
			printf("  round-trip mismatch at a[%u]: expected %u, got %u\n",
			    i, (unsigned)a_orig[i], (unsigned)a_work[i]);
		}
	}

	printf("Number of clock cycles for mp_NTT  (hardware): %d\n", cycles_ntt);
	printf("Number of clock cycles for mp_iNTT (hardware): %d\n", cycles_intt);

	if (errors == 0)
		printf("mp_NTT/mp_iNTT hardware benchmark terminated with no errors.\n");
	else
		printf("mp_NTT/mp_iNTT hardware benchmark terminated with %d errors\n", errors);

	return 0;
}
