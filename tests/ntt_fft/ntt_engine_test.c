/*
 * Standalone correctness test for the new ntt_engine.sv hardware NTT/iNTT
 * accelerator (keccak_ip/rtl/ntt_engine.sv), comparing it directly against
 * the REAL mp_NTT()/mp_iNTT()/mp_mkgmigm() from ng_mp31.c (not a hand
 * transliteration -- those functions are simple enough, and self-contained
 * enough within ng_mp31.c/ng_inner.h, to link directly and call as the
 * software reference).
 *
 * Unlike gauss_sampler_test.c, this test does NOT rely on a plain `fence`
 * to make the peripheral's DRAM writes visible to the CPU: this SoC config
 * (cv64a6_imac_crypto_config_pkg.sv) has DcacheFlushOnFence and
 * DcacheInvalidateOnFlush both set to 0 (the scoped fix from the Gaussian
 * sampler cache-coherency work replaced the global flush-on-fence approach
 * with a fixed non-cacheable DRAM scratch window instead -- see
 * GAUSS_HW_SCRATCH_ADDR in hawk_sign.c). ntt_engine writes its results back
 * to a[] as a second AXI master exactly like the sampler does, so it needs
 * the same treatment: every buffer the hardware touches (a[], gm[]/igm[])
 * lives in the PMA's uncached window (DRAM 0x80F00000 and up) so there is
 * no coherency question to begin with.
 *
 * Links only ng_mp31.c (plus bare-metal startup) -- no SHAKE/Keccak calls
 * are needed for this test, so sha3.c is not required even though
 * ng_inner.h declares its prototypes.
 */

#include <stddef.h>
#include <stdint.h>
#include <string.h>

#include "uart.h"
#include "ng_inner.h"
#include "keccak_axi.h"

/* true software references (ng_mp31.c), external linkage, not declared in
 * ng_inner.h (only the mp_NTT()/mp_iNTT() dispatchers are) -- called
 * directly here to bypass those dispatchers, which now redirect to
 * hardware for logn >= NTT_HW_MIN_LOGN. */
void mp_NTT_sw(unsigned logn, uint32_t *restrict a,
    const uint32_t *restrict gm, uint32_t p, uint32_t p0i);
void mp_iNTT_sw(unsigned logn, uint32_t *restrict a,
    const uint32_t *restrict igm, uint32_t p, uint32_t p0i);

#define KECCAK_AXI_BASE_ADDR 0x50000000UL

/* See the file header comment: same non-cacheable scratch-window
 * convention as GAUSS_HW_SCRATCH_ADDR, sized for the largest logn this
 * test exercises (logn=8, n=256): a[] (1024B) + gm[] (1024B) + igm[]
 * (1024B), rounded up. */
#define NTT_HW_SCRATCH_ADDR 0x80F00000UL
#define NTT_HW_SCRATCH_SIZE 0x1000u

#define MAX_LOGN 8u
#define MAX_N    (1u << MAX_LOGN)

static uint32_t volatile *const hw_a =
    (uint32_t volatile *)(NTT_HW_SCRATCH_ADDR + 0x000);
static uint32_t volatile *const hw_gm =
    (uint32_t volatile *)(NTT_HW_SCRATCH_ADDR + 0x400);
static uint32_t volatile *const hw_igm =
    (uint32_t volatile *)(NTT_HW_SCRATCH_ADDR + 0x800);

static uint32_t a_ref[MAX_N];
static uint32_t a_in[MAX_N];
static uint32_t gm[MAX_N];
static uint32_t igm[MAX_N];

static void
hw_ntt_run(uint64_t a_addr, uint64_t gm_addr, unsigned logn,
    uint32_t p, uint32_t p0i, unsigned mode)
{
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

	*ntt_a_addr   = a_addr;
	*ntt_gm_addr  = gm_addr;
	*ntt_logn     = logn;
	*ntt_p_val    = p;
	*ntt_p0i_val  = p0i;

	*ntt_ctrl = ((uint64_t)1 << KECCAK_NTT_CTRL_GO_BIT)
	    | ((uint64_t)mode << KECCAK_NTT_CTRL_MODE_OFFSET);
	while (((*ntt_ctrl) & ((uint64_t)1 << KECCAK_NTT_CTRL_DONE_BIT)) == 0);

	*ntt_ctrl = 0;
}

/* mode: 0 = forward NTT (mp_NTT, needs gm[]), 1 = inverse (mp_iNTT, igm[]) */
static int
run_case(const char *name, unsigned logn, unsigned prime_idx, unsigned mode)
{
	unsigned n = 1u << logn;
	uint32_t p   = PRIMES[prime_idx].p;
	uint32_t p0i = PRIMES[prime_idx].p0i;
	uint32_t g   = PRIMES[prime_idx].g;
	uint32_t ig  = PRIMES[prime_idx].ig;
	int errors = 0;

	/* deterministic pseudo-random input, reduced mod p */
	for (unsigned i = 0; i < n; i++) {
		uint32_t v = i * 2654435761u + 12345u;
		a_ref[i] = a_in[i] = v % p;
	}

	mp_mkgmigm(logn, gm, igm, g, ig, p, p0i);

	/* software reference: the real mp_NTT_sw()/mp_iNTT_sw(), not a copy.
	   Calling the mp_NTT()/mp_iNTT() dispatchers here would be wrong --
	   they now redirect to hardware for logn >= NTT_HW_MIN_LOGN, which
	   would make this a hardware-vs-hardware comparison instead of a
	   real hw-vs-sw check. */
	if (mode == 0) {
		mp_NTT_sw(logn, a_ref, gm, p, p0i);
	} else {
		mp_iNTT_sw(logn, a_ref, igm, p, p0i);
	}

	/* stage the hardware's inputs in the non-cacheable scratch window --
	   never cached in the first place, so no flush is needed before the
	   peripheral reads them and none is needed before the CPU reads its
	   results back below. */
	for (unsigned i = 0; i < n; i++) {
		hw_a[i]   = a_in[i];
		hw_gm[i]  = gm[i];
		hw_igm[i] = igm[i];
	}

	hw_ntt_run((uint64_t)(uintptr_t)hw_a,
	    (uint64_t)(uintptr_t)(mode ? hw_igm : hw_gm), logn, p, p0i, mode);

	for (unsigned i = 0; i < n; i++) {
		uint32_t got = hw_a[i];
		if (got != a_ref[i]) {
			errors++;
			printf("  a[%u] mismatch: sw=%u hw=%u\n", i,
			    (unsigned)a_ref[i], (unsigned)got);
		}
	}

	printf("%s (logn=%u, PRIMES[%u].p=%u): %s (%d mismatches)\n", name, logn,
	    prime_idx, (unsigned)p, errors == 0 ? "OK" : "MISMATCH", errors);
	return errors;
}

/*
 * Isolated correctness test for MODE=2 (mp_NTT_autoadj's "reduced
 * butterfly" phase, hawk_vrfy.c) -- see ntt_engine.sv's header comment
 * for the derivation this validates: calling the engine with
 * job_logn=(logn-1) and outer_q starting at 2 instead of 1 should
 * reproduce hawk_vrfy.c's `for (lm=1..logn-1) { ... u < (m>>1) ... }`
 * loop exactly. This only tests that reduced loop in isolation (fed an
 * arbitrary array, not a real auto-adjoint polynomial's unfolded output)
 * -- the "unfold" step that normally precedes it in mp_NTT_autoadj()
 * stays pure software and is untouched by this change, so it needs no
 * hardware-vs-software comparison here.
 *
 * Self-contained software reference (not linked from hawk_vrfy.c, which
 * has other dependencies) -- transliterated from hawk_vrfy.c's non-AVX2
 * mp_NTT_autoadj_sw() reduced-butterfly loop, using ng_inner.h's
 * mp_montymul()/mp_add()/mp_sub() (same primitives, already available
 * here via the shared header).
 */
static void
autoadj_reduced_sw(unsigned logn, uint32_t *restrict a,
    const uint32_t *restrict gm, uint32_t p, uint32_t p0i)
{
	size_t t = (size_t)1 << (logn - 1);
	for (unsigned lm = 1; lm < logn; lm++) {
		size_t m = (size_t)1 << lm;
		size_t ht = t >> 1;
		size_t v0 = 0;
		for (size_t u = 0; u < (m >> 1); u++) {
			uint32_t s = gm[u + m];
			for (size_t v = 0; v < ht; v++) {
				size_t k1 = v0 + v;
				size_t k2 = k1 + ht;
				uint32_t x1 = a[k1];
				uint32_t x2 = mp_montymul(a[k2], s, p, p0i);
				a[k1] = mp_add(x1, x2, p);
				a[k2] = mp_sub(x1, x2, p);
			}
			v0 += t;
		}
		t = ht;
	}
}

static int
run_autoadj_case(unsigned logn, unsigned prime_idx)
{
	unsigned n  = 1u << logn;
	unsigned hn = 1u << (logn - 1);
	uint32_t p   = PRIMES[prime_idx].p;
	uint32_t p0i = PRIMES[prime_idx].p0i;
	uint32_t g   = PRIMES[prime_idx].g;
	uint32_t ig  = PRIMES[prime_idx].ig;
	int errors = 0;

	for (unsigned i = 0; i < hn; i++) {
		uint32_t v = i * 2654435761u + 12345u;
		a_ref[i] = a_in[i] = v % p;
	}
	mp_mkgmigm(logn, gm, igm, g, ig, p, p0i);

	autoadj_reduced_sw(logn, a_ref, gm, p, p0i);

	for (unsigned i = 0; i < hn; i++) {
		hw_a[i]  = a_in[i];
	}
	/* gm[u+m] is indexed up to just under n (the reduced phase's last
	   stage has m=hn, u up to hn/2-1, so u+m up to ~1.5*hn-1) -- the
	   FULL n-sized table mp_mkgmigm() built must be staged, not just
	   the first hn entries a[] itself is confined to. */
	for (unsigned i = 0; i < n; i++) {
		hw_gm[i] = gm[i];
	}
	hw_ntt_run((uint64_t)(uintptr_t)hw_a, (uint64_t)(uintptr_t)hw_gm,
	    logn - 1, p, p0i, 2);

	for (unsigned i = 0; i < hn; i++) {
		uint32_t got = hw_a[i];
		if (got != a_ref[i]) {
			errors++;
			printf("  a[%u] mismatch: sw=%u hw=%u\n", i,
			    (unsigned)a_ref[i], (unsigned)got);
		}
	}

	printf("autoadj-reduced (logn=%u, PRIMES[%u].p=%u): %s (%d mismatches)\n",
	    logn, prime_idx, (unsigned)p, errors == 0 ? "OK" : "MISMATCH", errors);
	return errors;
}

int
main(void)
{
	int errors = 0;

	printf("NTT/iNTT hardware-vs-software test\n");

	/* logn=3 (n=8): every stage has only n/2=4 butterflies, so every
	   batch is a partial (< 16-triple) batch -- exercises the
	   is_last_triple_of_stage early-termination path on every stage.
	   logn=8 (n=256, HAWK-256's actual size): every stage has n/2=128
	   butterflies, so most batches are full 16-triple batches spanning
	   multiple LOAD/COMPUTE/WRITEBACK passes per stage. */
	static const unsigned logns[] = { 3u, 8u };

	/* PRIMES[0]/PRIMES[1] are P1/P2 (the only primes the old NTT_PRIME_SEL
	   design could express); PRIMES[2]/PRIMES[3] are ordinary entries from
	   the wider table ng_ntru.c/ng_poly.c actually iterate over during
	   solve_NTRU(). Exercising them here proves the widened NTT_P_VAL/
	   NTT_P0I_VAL registers work for genuinely arbitrary primes, not just
	   P1/P2 by coincidence. */
	for (unsigned li = 0; li < sizeof(logns) / sizeof(logns[0]); li++) {
		for (unsigned prime_idx = 0; prime_idx < 4; prime_idx++) {
			errors += run_case("NTT ", logns[li], prime_idx, 0);
			errors += run_case("iNTT", logns[li], prime_idx, 1);
		}
	}

	/* MODE=2 (mp_NTT_autoadj's reduced-butterfly phase): logn=3 is the
	   smallest case this function is ever called with ("Assumption: logn
	   >= 3"), giving job_logn=2 (right at NTT_HW_MIN_LOGN) -- the
	   tightest exercise of the mode-2 address generator; logn=8 matches
	   HAWK-256's real vrfy_ntt_norm() usage. */
	for (unsigned li = 0; li < sizeof(logns) / sizeof(logns[0]); li++) {
		for (unsigned prime_idx = 0; prime_idx < 4; prime_idx++) {
			errors += run_autoadj_case(logns[li], prime_idx);
		}
	}

	if (errors == 0)
		printf("NTT engine test terminated with no errors.\n");
	else
		printf("NTT engine test terminated with %d total mismatches\n", errors);

	return 0;
}
