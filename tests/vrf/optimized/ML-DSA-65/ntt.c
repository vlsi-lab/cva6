#include <stdint.h>
#include "params.h"
#include "ntt.h"
#include "reduce.h"

#include "vrf_axi.h"

/*
 * Forward/inverse NTT offloaded to the shared vrf_ip Keccak/NTT accelerator
 * (vrf_ip/rtl/ntt_engine.sv), replacing the software butterfly loops below.
 * Function names/signatures are unchanged so every existing call site
 * (poly.c, polyvec.c) needs no modification -- same integration shape as
 * Falcon's optimized/falcon512/vrfy.c.
 *
 * Twiddle tables: gm[]=zetas[] directly (no reordering), igm[] via a bit
 * permutation local to each power-of-two stage block. Both derived from
 * ntt_engine.sv's address-generator RTL (twiddle_idx = outer_q + u_q) and
 * verified bit-exact against ntt()/invntt_tomont() on real RTL simulation
 * (tests/app-tests/ntt-mldsa/main.c's own header comment has the full
 * derivation) before being used here -- not assumed from the
 * primitive-level round trip alone.
 */

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

#define VRF_AXI_BASE_ADDR 0x50000000UL
#define VRF_NTT_HW_SCRATCH_ADDR 0x80F09000UL

static uint32_t GM32[N];
static uint32_t iGM32[N];
static int tables_ready = 0;

static uint32_t
canon(int32_t z)
{
	int32_t r = z % Q;
	if (r < 0) {
		r += Q;
	}
	return (uint32_t)r;
}

static unsigned
bitfloor(unsigned x)
{
	unsigned p = 1;
	while (p * 2 <= x) {
		p <<= 1;
	}
	return p;
}

/* p0i = -1/Q mod 2^32. QINV (reduce.h) is +Q^-1 mod 2^32; p0i is its
 * negation, matching every other job on this accelerator (see
 * ntt_engine.sv's job_p0i_val_i doc comment). */
#define NTT_P0I ((uint32_t)(0u - QINV))

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
	tables_ready = 1;
}

static void
ntt_hw_dispatch(int32_t a[N], const uint32_t *gm, unsigned mode, unsigned noscale)
{
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
	unsigned i;

	if (!tables_ready) {
		build_hw_tables();
	}

	for (i = 0; i < N; i++) {
		scratch[i] = canon(a[i]);
	}

	__asm__ volatile ("fence" ::: "memory");

	*ntt_a_addr  = (uint64_t)VRF_NTT_HW_SCRATCH_ADDR;
	*ntt_gm_addr = (uint64_t)(uintptr_t)gm;
	*ntt_logn    = 8; /* log2(N), N=256 fixed for every ML-DSA security level */
	*ntt_p_val   = Q;
	*ntt_p0i_val = NTT_P0I;

	*ntt_ctrl = ((uint64_t)1 << VRF_NTT_CTRL_GO_BIT)
	    | ((uint64_t)mode << VRF_NTT_CTRL_MODE_BIT)
	    | ((uint64_t)noscale << VRF_NTT_CTRL_NOSCALE_BIT);
	while (((*ntt_ctrl) & ((uint64_t)1 << VRF_NTT_CTRL_DONE_BIT)) == 0);
	*ntt_ctrl = 0;

	for (i = 0; i < N; i++) {
		a[i] = (int32_t)scratch[i];
	}
}

/*************************************************
* Name:        ntt
*
* Description: Forward NTT, in-place. Output vector is in bitreversed
*              order. HW-offloaded (see header comment above).
*
* Arguments:   - uint32_t p[N]: input/output coefficient array
**************************************************/
void ntt(int32_t a[N]) {
	if (!tables_ready) {
		build_hw_tables();
	}
	ntt_hw_dispatch(a, GM32, /*mode=*/0, /*noscale=*/0);
}

/*************************************************
* Name:        invntt_tomont
*
* Description: Inverse NTT and multiplication by Montgomery factor 2^32,
*              in-place. HW-offloaded: NTT_CTRL.NOSCALE=1 skips the
*              per-stage scaling ntt_engine.sv's Falcon-convention inverse
*              mode applies, matching invntt_tomont()'s own butterfly shape
*              (see ntt_engine.sv's header comment); the single combined
*              n^-1/Montgomery correction multiply is applied here in
*              software afterward, exactly as the original reference does.
*
* Arguments:   - uint32_t p[N]: input/output coefficient array
**************************************************/
void invntt_tomont(int32_t a[N]) {
	const int32_t f = 41978; /* mont^2/256 */
	unsigned j;

	if (!tables_ready) {
		build_hw_tables();
	}
	ntt_hw_dispatch(a, iGM32, /*mode=*/1, /*noscale=*/1);

	for (j = 0; j < N; ++j) {
		a[j] = montgomery_reduce((int64_t)f * a[j]);
	}
}
