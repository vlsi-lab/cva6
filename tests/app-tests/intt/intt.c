/*
 * tests/app-tests/intt/intt.c
 *
 * Standalone SW-vs-HW microbenchmark: Falcon's inverse NTT modulo
 * q = 12289, at n = 512 (logn = 9) -- the real Falcon-512 ring degree,
 * not an arbitrary invented size.
 *
 * SW reference: mq_iNTT()/mq_montymul()/iGMb[], extracted verbatim from
 * tests/pqc/optimized/falcon512/vrfy.c (Falcon's own R=2^16 Montgomery
 * domain; iGMb[x] = R*((1/g)^rev(x)) mod q, g=7 so 1/g=8778 mod 12289).
 * Only the first N=512 entries of the original (n<=1024) table are
 * copied: mq_iNTT()'s iGMb[hm+i] indexing never exceeds n-1 for n=512.
 *
 * HW path: mq_iNTT_hw()/fmp_NTT_hw(mode=1), extracted verbatim from the
 * same file -- dispatches to ntt_engine.sv (vrf_ip/rtl/ntt_engine.sv)
 * via the vrf_ip AXI job registers (NTT_A_ADDR/NTT_GM_ADDR/NTT_LOGN/
 * NTT_P_VAL/NTT_P0I_VAL/NTT_CTRL, vrf_axi.h), using the engine's own,
 * separately-generated x2^32-Montgomery twiddle table iGM32[] -- see
 * vrfy.c's comment on mq_NTT_hw()/mq_iNTT_hw() for why iGMb[]/iGM32[]
 * are two different tables in two different Montgomery domains (R=2^16
 * vs R=2^32). mq_iNTT()/mq_iNTT_hw() are domain-preserving: a plain
 * (unscaled) input vector produces a plain inverse-NTT output regardless
 * of which Montgomery domain the twiddle table uses internally, so a
 * single plain uint16_t input can be fed to either path and the two
 * outputs compared directly.
 *
 * Input: a deterministic pseudo-random residue vector of degree 512
 * (fixed-seed LCG, values in [0, q)). mq_iNTT() is a linear transform
 * valid for any such vector -- it needs no "is this a real forward-NTT
 * output" precondition -- so this is sufficient to exercise the inverse
 * transform's full butterfly network without depending on the forward
 * NTT (kept in the separate tests/app-tests/ntt/ test).
 */

#include <stdint.h>
#include <string.h>

#include "encoding.h"
#include "vrf_axi.h"
#include "uart.h"

#define LOGN 9
#define N    (1u << LOGN)

#define VRF_AXI_BASE_ADDR 0x50000000UL

/* ===================================================================== */
/* SW reference: Falcon's native mq_iNTT() (16-bit Montgomery domain).   */
/* Extracted verbatim from tests/pqc/optimized/falcon512/vrfy.c.         */
/* ===================================================================== */

#define Q     12289
#define Q0I   12287
#define R      4091
#define R2    10952

/*
 * Table for inverse NTT, binary case:
 *   iGMb[x] = R*((1/g)^rev(x)) mod q
 * Since g = 7, 1/g = 8778 mod 12289.
 */
static const uint16_t iGMb[N] = {
	 4091,  4401,  1081,  1229,  2530,  6014,  7947,  5329,
	 2579,  4751,  6464, 11703,  7023,  2812,  5890, 10698,
	 3109,  2125,  1960, 10925, 10601, 10404,  4189,  1875,
	 5847,  8546,  4615,  5190, 11324, 10578,  5882, 11155,
	 8417, 12275, 10599,  7446,  5719,  3569,  5981, 10108,
	 4426,  8306, 10755,  4679, 11052,  1538, 11857,   100,
	 8247,  6625,  9725,  5145,  3412,  7858,  5831,  9460,
	 5217, 10740,  7882,  7506, 12172, 11292,  6049,    79,
	   13,  6938,  8886,  5453,  4586, 11455,  2903,  4676,
	 9843,  7621,  8822,  9109,  2083,  8507,  8685,  3110,
	 7015,  3269,  1367,  6397, 10259,  8435, 10527, 11559,
	11094,  2211,  1808,  7319,    48,  9547,  2560,  1228,
	 9438, 10787, 11800,  1820, 11406,  8966,  6159,  3012,
	 6109,  2796,  2203,  1652,   711,  7004,  1053,  8973,
	 5244,  1517,  9322, 11269,   900,  3888, 11133, 10736,
	 4949,  7616,  9974,  4746, 10270,   126,  2921,  6720,
	 6635,  6543,  1582,  4868,    42,   673,  2240,  7219,
	 1296, 11989,  7675,  8578, 11949,   989, 10541,  7687,
	 7085,  8487,  1004, 10236,  4703,   163,  9143,  4597,
	 6431, 12052,  2991, 11938,  4647,  3362,  2060, 11357,
	12011,  6664,  5655,  7225,  5914,  9327,  4092,  5880,
	 6932,  3402,  5133,  9394, 11229,  5252,  9008,  1556,
	 6908,  4773,  3853,  8780, 10325,  7737,  1758,  7103,
	11375, 12273,  8602,  3243,  6536,  7590,  8591, 11552,
	 6101,  3253,  9969,  9640,  4506,  3736,  6829, 10822,
	 9130,  9948,  3566,  2133,  3901,  6038,  7333,  6609,
	 3468,  4659,   625,  2700,  7738,  3443,  3060,  3388,
	 3526,  4418, 11911,  6232,  1730,  2558, 10340,  5344,
	 5286,  2190, 11562,  6199,  2482,  8756,  5387,  4101,
	 4609,  8605,  8226,   144,  5656,  8704,  2621,  5424,
	10812,  2959, 11346,  6249,  1715,  4951,  9540,  1888,
	 3764,    39,  8219,  2080,  2502,  1469, 10550,  8709,
	 5601,  1093,  3784,  5041,  2058,  8399, 11448,  9639,
	 2059,  9878,  7405,  2496,  7918, 11594,   371,  7993,
	 3073, 10326,    40, 10004,  9245,  7987,  5603,  4051,
	 7894,   676, 11380,  7379,  6501,  4981,  2628,  3488,
	10956,  7022,  6737,  9933,  7139,  2330,  3884,  5473,
	 7865,  6941,  5737,  5613,  9505, 11568, 11277,  2510,
	 6689,   386,  4462,   105,  2076, 10443,   119,  3955,
	 4370, 11505,  3672, 11439,   750,  3240,  3133,   754,
	 4013, 11929,  9210,  5378, 11881, 11018,  2818,  1851,
	 4966,  8181,  2688,  6205,  6814,   926,  2936,  4327,
	10175,  7089,  6047,  9410, 10492,  8950,  2472,  6255,
	  728,  7569,  6056, 10432, 11036,  2452,  2811,  3787,
	  945,  8998,  1244,  8815, 11017, 11218,  5894,  4325,
	 4639,  3819,  9826,  7056,  6786,  8670,  5539,  7707,
	 1361,  9812,  2949, 11265, 10301,  9108,   478,  6489,
	  101,  1911,  9483,  3608, 11997, 10536,   812,  8915,
	  637,  8159,  5299,  9128,  3512,  8290,  7068,  7922,
	 3036,  4759,  2163,  3937,  3755, 11306,  7739,  4922,
	11932,   424,  5538,  6228, 11131,  7778, 11974,  1097,
	 2890, 10027,  2569,  2250,  2352,   821,  2550, 11016,
	 7769,   136,   617,  3157,  5889,  9219,  6855,   120,
	 4405,  1825,  9635,  7214, 10261, 11393,  2441,  9562,
	11176,   599,  2085, 11465,  7233,  6177,  4801,  9926,
	 9010,  4514,  9455, 11352, 11670,  6174,  7950,  9766,
	 6896, 11603,  3213,  8473,  9873,  2835, 10422,  3732,
	 7961,  1457, 10857,  8069,   832,  1628,  3410,  4900,
	10855,  5111,  9543,  6325,  7431,  4083,  3072,  8847,
	 9853, 10122,  5259, 11413,  6556,   303,  1465,  3871,
	 4873,  5813, 10017,  6898,  3311,  5947,  8637,  5852,
	 3856,   928,  4933,  8530,  1871,  2184,  5571,  5879,
	 3481, 11597,  9511,  8153,    35,  2609,  5963,  8064,
	 1080, 12039,  8444,  3052,  3813, 11065,  6736,  8454
};

static inline uint32_t
mq_add(uint32_t x, uint32_t y)
{
	uint32_t d;

	d = x + y - Q;
	d += Q & -(d >> 31);
	return d;
}

static inline uint32_t
mq_sub(uint32_t x, uint32_t y)
{
	uint32_t d;

	d = x - y;
	d += Q & -(d >> 31);
	return d;
}

/*
 * Division by 2 modulo q. Operand must be in the 0..q-1 range.
 */
static inline uint32_t
mq_rshift1(uint32_t x)
{
	x += Q & -(x & 1);
	return (x >> 1);
}

/*
 * Montgomery multiplication modulo q. If we set R = 2^16 mod q, then
 * this function computes: x * y / R mod q
 * Operands must be in the 0..q-1 range.
 */
static inline uint32_t
mq_montymul(uint32_t x, uint32_t y)
{
	uint32_t z, w;

	z = x * y;
	w = ((z * Q0I) & 0xFFFF) * Q;
	z = (z + w) >> 16;
	z -= Q;
	z += Q & -(z >> 31);
	return z;
}

/*
 * Compute the inverse NTT on a ring element, binary case (SW reference).
 */
static void
mq_iNTT(uint16_t *a, unsigned logn)
{
	size_t n, t, m;
	uint32_t ni;

	n = (size_t)1 << logn;
	t = 1;
	m = n;
	while (m > 1) {
		size_t hm, dt, i, j1;

		hm = m >> 1;
		dt = t << 1;
		for (i = 0, j1 = 0; i < hm; i ++, j1 += dt) {
			size_t j, j2;
			uint32_t s;

			j2 = j1 + t;
			s = iGMb[hm + i];
			for (j = j1; j < j2; j ++) {
				uint32_t u, v, w;

				u = a[j];
				v = a[j + t];
				a[j] = (uint16_t)mq_add(u, v);
				w = mq_sub(u, v);
				a[j + t] = (uint16_t)
					mq_montymul(w, s);
			}
		}
		t = dt;
		m = hm;
	}

	/*
	 * To complete the inverse NTT, we must now divide all values by
	 * n (the vector size), in Montgomery representation (i.e. also
	 * multiply by R = 2^16).
	 */
	ni = R;
	for (m = n; m > 1; m >>= 1) {
		ni = mq_rshift1(ni);
	}
	for (m = 0; m < n; m ++) {
		a[m] = (uint16_t)mq_montymul(a[m], ni);
	}
}

/* ===================================================================== */
/* HW path: mq_iNTT_hw()/fmp_NTT_hw(mode=1), extracted verbatim from     */
/* vrfy.c.                                                                */
/* ===================================================================== */

#define VRF_Q_P0I32   4143984639u   /* -1/12289 mod 2^32 */

/*
 * q=12289 inverse-NTT twiddle table in the engine's x2^32-Montgomery
 * domain (see the big comment at the top of this file for provenance).
 */
static const uint32_t iGM32[N] = {
	2147471359,        553,       5310,        819,       1446,        348,
	      3386,       6271,       9508,       3716,      11437,       5659,
	      5850,        694,       4775,       8339,      12191,       2526,
	      2966,      11830,        405,       9123,       9311,       7289,
	      8986,       5885,       8175,      10738,      10766,       8659,
	       700,       3024,       6229,       8230,       8603,       4722,
	      5231,       6868,        436,       5816,       8679,       6525,
	      8187,       3908,       7395,      12284,       1152,       7926,
	      2586,       2815,       2741,      10858,      11383,      11816,
	       836,       7544,      10666,       8227,      11752,       4562,
	       312,       6755,       4351,       7982,       8158,      10173,
	       882,       1844,       4156,       2224,       8644,       3916,
	     10619,        159,       5149,       8480,       2638,       5989,
	      1418,       8092,       1775,       7668,        451,       3423,
	      1317,       6181,       8795,       6043,       7283,       6393,
	     11564,       9157,      12161,       7312,       1366,       4918,
	     11699,      12198,       1304,      11532,       6451,       4765,
	      8154,       4257,       4191,       4833,       2318,      11980,
	     10393,       9997,       9481,        650,      10594,         51,
	      7912,       2720,       9889,       1921,       7179,         45,
	      3188,       8365,       2077,      11922,       5384,      11953,
	      8596,       6658,      10981,       7130,       3974,       3404,
	     12177,       6398,      10412,       1231,       8833,        800,
	        15,       9896,       5003,       1459,        565,      12272,
	      9781,       1946,       1419,       9571,       3844,       7758,
	      4293,       8223,      11525,        632,       4313,        936,
	     12186,       7420,      10892,      10678,       8934,       2711,
	      9498,       1215,       4711,      11995,       1377,       8898,
	     10189,       3217,      10890,       7720,       6923,       2380,
	      4653,      12236,      10253,      11850,      10207,       5261,
	      1141,       3946,       7601,       9733,      10630,       4139,
	      9832,       3641,      11245,       4338,       5765,      10158,
	       116,      11807,      10283,       7064,        273,      10519,
	      2271,       3912,       8424,      10339,       6876,       6601,
	     10079,        284,        927,       6954,       3041,      12154,
	      6526,       5089,      12136,       7204,       4129,      11447,
	     11079,       4604,       1008,       3863,      11772,       9564,
	      1101,       6231,      10482,       6449,       6035,       3951,
	      1574,       5325,       2020,       1353,       8191,       9824,
	      2642,      11905,       5399,       9560,       9396,      10114,
	      8035,        302,       6611,       7914,      11812,       7279,
	     11427,       3158,       6348,      12185,       6757,       2646,
	      5617,        179,        541,       1354,       9642,       5278,
	     10391,       7039,       6801,       6277,       6339,      11163,
	      2702,       2333,        735,       5633,      11656,      10046,
	      3107,      11456,      12287,       9331,       8086,       1997,
	      4021,      11472,       1444,       9679,      11720,       6390,
	      2424,       8997,       7242,       7199,       5281,       7084,
	      7651,       9949,      10709,      10379,       9637,      10172,
	      6028,       5887,       7701,      10165,       5183,       9610,
	      7424,       6019,       6795,       9692,      10837,       3067,
	      8583,      12009,       6753,       9019,       3779,       9935,
	      4732,       6187,       2497,       6363,      10289,       3649,
	     12127,       6182,       5684,        960,         18,       2044,
	      1088,      11582,        678,       7353,       7239,       2762,
	      5121,       3935,       2311,       1627,       8556,       8943,
	      1541,       5674,        260,       3581,       4792,       8904,
	      5697,       7898,       2155,       4394,        236,       4952,
	     11534,       1654,       4793,      10383,       9769,       8776,
	       779,       9264,       3392,       2856,        668,       4852,
	      8111,       2105,       6568,       5762,       6482,       1458,
	      5711,       4026,        467,       2509,       4425,       6827,
	      1205,        290,       6918,       7274,       3827,       7193,
	     11579,       6764,       4875,       8771,       1931,       4901,
	      6494,       6917,       6351,       4333,       7020,      10664,
	      5730,       7549,       4193,       7791,       6521,       9983,
	      6372,      10814,       8037,       3260,        952,       7062,
	      9810,       7970,       3088,       7933,        840,       1171,
	       486,       6032,       1342,       6289,       6017,       1907,
	      5489,       7491,       7957,       7830,       2451,      12063,
	      8874,      12283,       6298,      11969,       8735,       3326,
	      2981,       9437,       5408,      10582,       9876,       7272,
	      2968,       2499,       6729,      10390,       5290,       8106,
	      7679,       2205,       8744,       4348,       3461,       6595,
	      5747,       8114,       3378,       6728,      10285,      10022,
	      3721,      10176,      10539,       4729,       9075,       2337,
	      7445,        211,       7915,       7157,       5974,      12044,
	      7292,       7415,       3824,       2756,      11419,       3615,
	      4762,       1401,       4097,        986,       6496,       9875,
	     10554,       2336,       2999,      11481,       4286,      10159,
	      7487,        884,      10155,       2087,       7556,       4623,
	      1546,        780,      10199,       5718,       7327,      10024,
	     11396,       6465,       9722,        708,      11199,      10038,
	      7408,       6933,       4003,       9428,        484,       3074,
	      9409,       4763,       6157,         54,       2121,       3264,
	      2519,       2034
};

#define VRF_NTT_HW_SCRATCH_ADDR  0x80F09000UL

/*
 * a[]/gm[] are staged through a fixed non-cacheable DRAM scratch window
 * (same convention as tests/pqc/optimized/falcon512/vrfy.c's
 * VRF_NTT_HW_SCRATCH_ADDR; this SoC's DcacheFlushOnFence/
 * DcacheInvalidateOnFlush are both 0, so writing into cacheable memory
 * could leave a stale D$ line masking the hardware's AXI writes).
 */
static void
fmp_NTT_hw(unsigned logn, uint32_t *restrict a, const uint32_t *restrict gm,
    uint32_t p, uint32_t p0i, unsigned mode)
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
	    | ((uint64_t)mode << VRF_NTT_CTRL_MODE_BIT);
	while (((*ntt_ctrl) & ((uint64_t)1 << VRF_NTT_CTRL_DONE_BIT)) == 0);
	*ntt_ctrl = 0;

	for (size_t i = 0; i < n; i++) {
		a[i] = scratch[i];
	}
}

/*
 * uint16_t-interface dispatcher, drop-in replacement for mq_iNTT() above
 * -- plain-domain in, plain-domain out (see the big comment at the top
 * of this file).
 */
static void
mq_iNTT_hw(uint16_t *a, unsigned logn)
{
	size_t n = (size_t)1 << logn;
	uint32_t tmp[N];

	for (size_t i = 0; i < n; i++) {
		tmp[i] = a[i];
	}
	fmp_NTT_hw(logn, tmp, iGM32, Q, VRF_Q_P0I32, 1);
	for (size_t i = 0; i < n; i++) {
		a[i] = (uint16_t)tmp[i];
	}
}

/* ===================================================================== */
/* Test driver                                                           */
/* ===================================================================== */

static void
gen_poly(uint16_t *a, unsigned n, uint32_t seed)
{
	uint32_t x = seed;
	unsigned i;

	for (i = 0; i < n; i ++) {
		x = x * 1103515245u + 12345u;
		a[i] = (uint16_t)(x % Q);
	}
}

int
main(void)
{
	static uint16_t a_sw[N], a_hw[N];
	uint32_t cycles_sw, cycles_hw;
	unsigned mismatches, i;

	print_uart("=== intt: Falcon inverse NTT mod 12289, n=");
	print_uart_dec((int)N);
	print_uart(" ===\n");

	gen_poly(a_sw, N, 0xC0FFEEu);
	memcpy(a_hw, a_sw, sizeof a_sw);

	clear_csr(mcountinhibit, 1);

	write_csr(mcycle, 0);
	mq_iNTT(a_sw, LOGN);
	cycles_sw = (uint32_t)read_csr(mcycle);
	print_uart("SW cycles: ");
	print_uart_dec((int)cycles_sw);
	print_uart("\n");

	write_csr(mcycle, 0);
	mq_iNTT_hw(a_hw, LOGN);
	cycles_hw = (uint32_t)read_csr(mcycle);
	print_uart("HW cycles: ");
	print_uart_dec((int)cycles_hw);
	print_uart("\n");

	mismatches = 0;
	for (i = 0; i < N; i ++) {
		if (a_sw[i] != a_hw[i]) {
			if (mismatches < 8) {
				print_uart("  mismatch[");
				print_uart_dec((int)i);
				print_uart("]: SW=");
				print_uart_dec((int)(unsigned)a_sw[i]);
				print_uart(" HW=");
				print_uart_dec((int)(unsigned)a_hw[i]);
				print_uart("\n");
			}
			mismatches ++;
		}
	}

	if (cycles_sw > 0 && cycles_hw > 0) {
		print_uart("Speedup: ");
		print_uart_dec((int)(cycles_sw / cycles_hw));
		print_uart(".");
		{
			uint32_t frac = ((cycles_sw * 100U) / cycles_hw) % 100U;
			if (frac < 10) {
				print_uart("0");
			}
			print_uart_dec((int)frac);
		}
		print_uart("x\n");
	}

	if (mismatches == 0) {
		print_uart("[PASS] HW matches SW element-wise (");
		print_uart_dec((int)N);
		print_uart(" coefficients)\n");
		return 0;
	}

	print_uart("[FAIL] ");
	print_uart_dec((int)mismatches);
	print_uart(" / ");
	print_uart_dec((int)N);
	print_uart(" coefficients mismatched\n");
	return 1;
}
