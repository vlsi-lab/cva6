/*
 * tests/app-tests/ntt-mldsa/main.c
 *
 * Bit-exact SW-vs-HW validation of ntt_engine.sv (vrf_ip/rtl/ntt_engine.sv)
 * against ML-DSA's REAL reference ntt()/invntt_tomont() (verbatim copies of
 * tests/vrf/optimized/ML-DSA-44/ntt.c and reduce.c's montgomery_reduce/
 * QINV, q=8380417, n=256), not merely a self-consistent forward+inverse
 * round trip. This is the primitive-level correctness gate Phase 3 (real
 * driver integration into tests/vrf/optimized/ML-DSA-*) depends on: an
 * earlier version of this test only proved forward-then-inverse recovered
 * the original polynomial for an independently-derived table, which does
 * NOT prove the hardware would produce the SAME values ML-DSA's own
 * pointwise-multiply steps (which combine hardware-NTT'd and software-NTT'd
 * operands, e.g. polyvec_matrix_pointwise_montgomery combining a HW-NTT'd
 * mat[] against a HW-NTT'd z) expect.
 *
 * The two open questions this test resolves, derived from first principles
 * and checked here on real RTL (not assumed):
 *
 *  1. Forward table: ntt_engine.sv's twiddle_idx = outer_q + u_q (see its
 *     header comment: outer(m) starts at 1, doubles per stage) turns out to
 *     visit the exact same index sequence, in the exact same order, as
 *     ML-DSA's own `zeta = zetas[++k]` (k starts at 0). Consequently
 *     gm[idx] = zetas[idx] mod Q, taken DIRECTLY from ML-DSA's own zetas[]
 *     table with no reordering, is the correct forward twiddle table --
 *     confirmed by symbolic derivation matching the RTL's stage/index
 *     progression to software's loop nest exactly (see result.md's Phase 3
 *     notes), not just by this test's empirical pass/fail.
 *
 *  2. Inverse table: ntt_engine.sv's inverse-mode butterfly (k1'=x1+x2,
 *     k2'=montgomery_reduce((x1-x2)*s), matching invntt_tomont()'s
 *     structure exactly) uses the SAME idx=outer_q+u_q formula, but here
 *     outer_q(=hm) DESCENDS from n/2 while u_q ascends within a stage --
 *     the opposite direction from software's k, which DESCENDS as `start`
 *     ascends within the same stage. Working through the exact index
 *     arithmetic shows this is a bit permutation local to each power-of-two
 *     stage block: k(idx) = idx XOR (bitfloor(idx) - 1), where bitfloor(idx)
 *     is the largest power of two <= idx. So:
 *       igm[idx] = (Q - zetas[ idx XOR (bitfloor(idx)-1) ]) mod Q
 *     This was verified with 0/255 mismatches against a direct simulation
 *     of both the RTL's exact (stage, u) traversal and software's exact
 *     (len, start, k) traversal, in a standalone host-side check (not
 *     reproduced on-target here since it needs no hardware) before writing
 *     this table into the test below.
 *
 * Both tables are FIXED (n=256 is the same for every ML-DSA security level),
 * so they are computed once here and are the exact tables Phase 3's real
 * driver code should embed.
 */

#include <stdint.h>
#include <string.h>

#include "encoding.h"
#include "vrf_axi.h"
#include "uart.h"

#define LOGN 8
#define N    (1u << LOGN)

#define VRF_AXI_BASE_ADDR 0x50000000UL
#define VRF_NTT_HW_SCRATCH_ADDR 0x80F09000UL

#define Q 8380417
#define QINV 58728449u /* q^-1 mod 2^32, verbatim from ML-DSA reduce.h */

/* ===================================================================== */
/* ML-DSA's REAL reference: zetas[], montgomery_reduce(), ntt(),         */
/* invntt_tomont() -- byte-for-byte copies of                            */
/* tests/vrf/optimized/ML-DSA-44/{ntt.c,reduce.c}, not reproduced from   */
/* memory/derived tables.                                                */
/* ===================================================================== */

static const int32_t zetas[N] = {
         0,    25847, -2608894,  -518909,   237124,  -777960,  -876248,   466468,
   1826347,  2353451,  -359251, -2091905,  3119733, -2884855,  3111497,  2680103,
   2725464,  1024112, -1079900,  3585928,  -549488, -1119584,  2619752, -2108549,
  -2118186, -3859737, -1399561, -3277672,  1757237,   -19422,  4010497,   280005,
   2706023,    95776,  3077325,  3530437, -1661693, -3592148, -2537516,  3915439,
  -3861115, -3043716,  3574422, -2867647,  3539968,  -300467,  2348700,  -539299,
  -1699267, -1643818,  3505694, -3821735,  3507263, -2140649, -1600420,  3699596,
    811944,   531354,   954230,  3881043,  3900724, -2556880,  2071892, -2797779,
  -3930395, -1528703, -3677745, -3041255, -1452451,  3475950,  2176455, -1585221,
  -1257611,  1939314, -4083598, -1000202, -3190144, -3157330, -3632928,   126922,
   3412210,  -983419,  2147896,  2715295, -2967645, -3693493,  -411027, -2477047,
   -671102, -1228525,   -22981, -1308169,  -381987,  1349076,  1852771, -1430430,
  -3343383,   264944,   508951,  3097992,    44288, -1100098,   904516,  3958618,
  -3724342,    -8578,  1653064, -3249728,  2389356,  -210977,   759969, -1316856,
    189548, -3553272,  3159746, -1851402, -2409325,  -177440,  1315589,  1341330,
   1285669, -1584928,  -812732, -1439742, -3019102, -3881060, -3628969,  3839961,
   2091667,  3407706,  2316500,  3817976, -3342478,  2244091, -2446433, -3562462,
    266997,  2434439, -1235728,  3513181, -3520352, -3759364, -1197226, -3193378,
    900702,  1859098,   909542,   819034,   495491, -1613174,   -43260,  -522500,
   -655327, -3122442,  2031748,  3207046, -3556995,  -525098,  -768622, -3595838,
    342297,   286988, -2437823,  4108315,  3437287, -3342277,  1735879,   203044,
   2842341,  2691481, -2590150,  1265009,  4055324,  1247620,  2486353,  1595974,
  -3767016,  1250494,  2635921, -3548272, -2994039,  1869119,  1903435, -1050970,
  -1333058,  1237275, -3318210, -1430225,  -451100,  1312455,  3306115, -1962642,
  -1279661,  1917081, -2546312, -1374803,  1500165,   777191,  2235880,  3406031,
   -542412, -2831860, -1671176, -1846953, -2584293, -3724270,   594136, -3776993,
  -2013608,  2432395,  2454455,  -164721,  1957272,  3369112,   185531, -1207385,
  -3183426,   162844,  1616392,  3014001,   810149,  1652634, -3694233, -1799107,
  -3038916,  3523897,  3866901,   269760,  2213111,  -975884,  1717735,   472078,
   -426683,  1723600, -1803090,  1910376, -1667432, -1104333,  -260646, -3833893,
  -2939036, -2235985,  -420899, -2286327,   183443,  -976891,  1612842, -3545687,
   -554416,  3919660,   -48306, -1362209,  3937738,  1400424,  -846154,  1976782
};

static int32_t
montgomery_reduce(int64_t a)
{
	int32_t t;

	t = (int64_t)(int32_t)a * QINV;
	t = (a - (int64_t)t * Q) >> 32;
	return t;
}

static void
ref_ntt(int32_t a[N])
{
	unsigned int len, start, j, k;
	int32_t zeta, t;

	k = 0;
	for (len = 128; len > 0; len >>= 1) {
		for (start = 0; start < N; start = j + len) {
			zeta = zetas[++k];
			for (j = start; j < start + len; ++j) {
				t = montgomery_reduce((int64_t)zeta * a[j + len]);
				a[j + len] = a[j] - t;
				a[j] = a[j] + t;
			}
		}
	}
}

static void
ref_invntt_tomont(int32_t a[N])
{
	unsigned int start, len, j, k;
	int32_t t, zeta;
	const int32_t f = 41978; /* mont^2/256 */

	k = 256;
	for (len = 1; len < N; len <<= 1) {
		for (start = 0; start < N; start = j + len) {
			zeta = -zetas[--k];
			for (j = start; j < start + len; ++j) {
				t = a[j];
				a[j] = t + a[j + len];
				a[j + len] = t - a[j + len];
				a[j + len] = montgomery_reduce((int64_t)zeta * a[j + len]);
			}
		}
	}

	for (j = 0; j < N; ++j) {
		a[j] = montgomery_reduce((int64_t)f * a[j]);
	}
}

static uint32_t
canon(int32_t z)
{
	int32_t r = z % Q;
	if (r < 0) {
		r += Q;
	}
	return (uint32_t)r;
}

/* ===================================================================== */
/* HW twiddle tables: gm[]=zetas[] direct; igm[] via the bit-permutation  */
/* derived above. Built once at runtime from the real zetas[] table --   */
/* no separate modpow/root-of-unity derivation, no borrowed constants.   */
/* ===================================================================== */

static uint32_t GM32[N];
static uint32_t iGM32[N];

static unsigned
bitfloor(unsigned x)
{
	unsigned p = 1;
	while (p * 2 <= x) {
		p <<= 1;
	}
	return p;
}

static void
build_hw_tables(void)
{
	unsigned idx;

	GM32[0] = 0;
	iGM32[0] = 0;
	for (idx = 1; idx < N; idx++) {
		unsigned kidx = idx ^ (bitfloor(idx) - 1);

		GM32[idx] = canon(zetas[idx]);
		iGM32[idx] = (Q - (int32_t)canon(zetas[kidx])) % Q;
	}
}

/* ===================================================================== */
/* HW dispatch (same shape as tests/app-tests/ntt/intt.c's, plus the      */
/* NOSCALE control bit).                                                  */
/* ===================================================================== */

static void
fmp_NTT_hw(unsigned logn, uint32_t *restrict a, const uint32_t *restrict gm,
    uint32_t p, uint32_t p0i, unsigned mode, unsigned noscale)
{
	size_t n = (size_t)1 << logn;
	uint32_t volatile *scratch = (uint32_t volatile *)VRF_NTT_HW_SCRATCH_ADDR;

	uint64_t volatile *ntt_a_addr = (uint64_t volatile *)
	    (VRF_AXI_BASE_ADDR + VRF_NTT_A_ADDR_REG_OFFSET);
	uint64_t volatile *ntt_gm_addr = (uint64_t volatile *)
	    (VRF_AXI_BASE_ADDR + VRF_NTT_GM_ADDR_REG_OFFSET);
	uint64_t volatile *ntt_logn = (uint64_t volatile *)
	    (VRF_AXI_BASE_ADDR + VRF_NTT_LOGN_REG_OFFSET);
	uint64_t volatile *ntt_p_val = (uint64_t volatile *)
	    (VRF_AXI_BASE_ADDR + VRF_NTT_P_VAL_REG_OFFSET);
	uint64_t volatile *ntt_p0i_val = (uint64_t volatile *)
	    (VRF_AXI_BASE_ADDR + VRF_NTT_P0I_VAL_REG_OFFSET);
	uint64_t volatile *ntt_ctrl = (uint64_t volatile *)
	    (VRF_AXI_BASE_ADDR + VRF_NTT_CTRL_REG_OFFSET);

	for (size_t i = 0; i < n; i++) {
		scratch[i] = a[i];
	}

	__asm__ volatile ("fence" ::: "memory");

	*ntt_a_addr  = (uint64_t)VRF_NTT_HW_SCRATCH_ADDR;
	*ntt_gm_addr = (uint64_t)(uintptr_t)gm;
	*ntt_logn    = logn;
	*ntt_p_val   = p;
	*ntt_p0i_val = p0i;

	*ntt_ctrl = ((uint64_t)1 << VRF_NTT_CTRL_GO_BIT)
	    | ((uint64_t)mode << VRF_NTT_CTRL_MODE_BIT)
	    | ((uint64_t)noscale << VRF_NTT_CTRL_NOSCALE_BIT);
	while (((*ntt_ctrl) & ((uint64_t)1 << VRF_NTT_CTRL_DONE_BIT)) == 0);
	*ntt_ctrl = 0;

	for (size_t i = 0; i < n; i++) {
		a[i] = scratch[i];
	}
}

/* p0i = -1/p mod 2^32 via Newton's iteration; self-checked against QINV
 * below rather than trusted blindly. */
static uint32_t
modinv32_neg(uint32_t p)
{
	uint32_t x = p;
	int i;

	for (i = 0; i < 5; i++) {
		x = x * (2u - p * x);
	}
	return (uint32_t)(0u - x);
}

/* ===================================================================== */
/* Test driver                                                            */
/* ===================================================================== */

static int32_t sw_ref[N];
static uint32_t hw_work[N];

static void
gen_poly(int32_t *a, unsigned n, uint32_t seed)
{
	uint32_t x = seed;
	unsigned i;

	for (i = 0; i < n; i++) {
		x = x * 1103515245u + 12345u;
		a[i] = (int32_t)(x % Q);
	}
}

int
main(void)
{
	uint32_t p0i;
	unsigned i;
	int fail_p0i, fail_fwd, fail_inv;
	uint32_t cycles;

	clear_csr(mcountinhibit, 1);

	p0i = modinv32_neg(Q);
	fail_p0i = (p0i != (uint32_t)(0u - QINV));

	build_hw_tables();

	gen_poly(sw_ref, N, 0xA5A5A5A5u);
	for (i = 0; i < N; i++) {
		hw_work[i] = canon(sw_ref[i]);
	}

	write_csr(mcycle, 0);

	/* Forward: HW mode=0 vs. SW ntt(), same input. */
	fmp_NTT_hw(LOGN, hw_work, GM32, Q, p0i, /*mode=*/0, /*noscale=*/0);
	ref_ntt(sw_ref);

	fail_fwd = 0;
	for (i = 0; i < N; i++) {
		if (hw_work[i] != canon(sw_ref[i])) {
			fail_fwd = 1;
			break;
		}
	}

	/* Inverse: HW mode=1/NOSCALE=1, then software's own single final
	 * f-multiply pass (exactly what Phase 3's real driver will do),
	 * compared against SW invntt_tomont()'s full output (same input:
	 * the NTT-domain values from the forward step above, on both
	 * sides). */
	fmp_NTT_hw(LOGN, hw_work, iGM32, Q, p0i, /*mode=*/1, /*noscale=*/1);
	{
		const int32_t f = 41978;
		for (i = 0; i < N; i++) {
			int32_t v = (int32_t)hw_work[i];
			int64_t t = (int64_t)f * v;
			int32_t r = montgomery_reduce(t);
			hw_work[i] = canon(r);
		}
	}
	ref_invntt_tomont(sw_ref);

	fail_inv = 0;
	for (i = 0; i < N; i++) {
		if (hw_work[i] != canon(sw_ref[i])) {
			fail_inv = 1;
			break;
		}
	}

	cycles = (uint32_t)read_csr(mcycle);

	print_uart("=== ntt-mldsa: bit-exact vs. real ML-DSA ntt()/invntt_tomont() ===\n");
	print_uart("p0i self-check: ");
	print_uart(fail_p0i ? "[FAIL]\n" : "[PASS]\n");
	print_uart("Forward NTT bit-exact vs. ntt(): ");
	print_uart(fail_fwd ? "[FAIL]\n" : "[PASS]\n");
	print_uart("Inverse NTT (NOSCALE+SW final mul) bit-exact vs. invntt_tomont(): ");
	print_uart(fail_inv ? "[FAIL]\n" : "[PASS]\n");
	print_uart("HW cycles (both transforms): ");
	print_uart_dec((int)cycles);
	print_uart("\n");

	if (!fail_p0i && !fail_fwd && !fail_inv) {
		print_uart("FINAL STATUS: ALL TESTS PASSED\n");
	} else {
		print_uart("FINAL STATUS: TEST(S) FAILED\n");
	}

	return fail_p0i || fail_fwd || fail_inv;
}
