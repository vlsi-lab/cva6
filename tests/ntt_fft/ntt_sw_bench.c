/*
 * Pure-software single-operation benchmark for mp_NTT()/mp_iNTT(),
 * mirroring tests/keccak64/keccak_noopt.c: measures ONLY the isolated
 * cost of one forward and one inverse transform via the mcycle CSR, with
 * no hardware involved at all -- calls mp_NTT_sw()/mp_iNTT_sw() directly
 * (ng_mp31.c, exposed with external linkage specifically for this),
 * bypassing the mp_NTT()/mp_iNTT() dispatchers (and therefore the
 * hardware) entirely.
 *
 * Correctness check: NTT and iNTT are exact inverses of each other
 * (mp_iNTT()'s n^-1 scaling is built into every stage, not a separate
 * pass -- see ng_mp31.c's header comment), so
 * mp_iNTT_sw(mp_NTT_sw(x)) must reconstruct x exactly. A self-contained
 * round-trip check, no external expected-vector constants needed.
 *
 * n=256, p=P1: matches HAWK-256's actual NTT size and one of its two
 * NTT-friendly primes, for a realistic single-operation cost.
 */

#include <stddef.h>
#include <stdint.h>
#include <string.h>

#include "uart.h"
#include "encoding.h"
#include "ng_inner.h"

#define N     256u
#define LOGN  8u

void mp_NTT_sw(unsigned logn, uint32_t *restrict a,
    const uint32_t *restrict gm, uint32_t p, uint32_t p0i);
void mp_iNTT_sw(unsigned logn, uint32_t *restrict a,
    const uint32_t *restrict igm, uint32_t p, uint32_t p0i);

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

	printf("mp_NTT/mp_iNTT pure-software single-operation benchmark (n=%u, P1)\n", N);

	clear_csr(mcountinhibit, 1);

	write_csr(mcycle, 0);
	mp_NTT_sw(LOGN, a_work, gm, p, p0i);
	cycles_ntt = read_csr(mcycle);

	write_csr(mcycle, 0);
	mp_iNTT_sw(LOGN, a_work, igm, p, p0i);
	cycles_intt = read_csr(mcycle);

	for (unsigned i = 0; i < N; i++) {
		if (a_work[i] != a_orig[i]) {
			errors++;
			printf("  round-trip mismatch at a[%u]: expected %u, got %u\n",
			    i, (unsigned)a_orig[i], (unsigned)a_work[i]);
		}
	}

	printf("Number of clock cycles for mp_NTT  (software): %d\n", cycles_ntt);
	printf("Number of clock cycles for mp_iNTT (software): %d\n", cycles_intt);

	if (errors == 0)
		printf("mp_NTT/mp_iNTT software benchmark terminated with no errors.\n");
	else
		printf("mp_NTT/mp_iNTT software benchmark terminated with %d errors\n", errors);

	return 0;
}
