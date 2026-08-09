/*
 * tests/app-tests/ntt/ntt.c
 *
 * Standalone SW-vs-HW microbenchmark: Falcon's forward NTT modulo
 * q = 12289, at n = 512 (logn = 9) -- the real Falcon-512 ring degree,
 * not an arbitrary invented size.
 *
 * SW reference: mq_NTT()/mq_montymul()/GMb[], extracted verbatim from
 * tests/pqc/optimized/falcon512/vrfy.c (Falcon's own R=2^16 Montgomery
 * domain; GMb[x] = R*(g^rev(x)) mod q, g=7 a 2048-th primitive root of 1
 * modulo q, rev() the 10-bit bit-reversal function). Only the first
 * N=512 entries of the original (n<=1024) table are copied: mq_NTT()'s
 * GMb[m+i] indexing never exceeds n-1 for n=512.
 *
 * HW path: mq_NTT_hw()/fmp_NTT_hw(), extracted verbatim from the same
 * file -- dispatches to ntt_engine.sv (vrf_ip/rtl/ntt_engine.sv) via
 * the vrf_ip AXI job registers (NTT_A_ADDR/NTT_GM_ADDR/NTT_LOGN/
 * NTT_P_VAL/NTT_P0I_VAL/NTT_CTRL, vrf_axi.h), using the engine's own,
 * separately-generated x2^32-Montgomery twiddle table GM32[] -- see
 * vrfy.c's comment on mq_NTT_hw() for why GMb[]/GM32[] are two different
 * tables in two different Montgomery domains (R=2^16 vs R=2^32), even
 * though both encode the same underlying root g=7. mq_NTT()/mq_NTT_hw()
 * are domain-preserving: a plain (unscaled) input polynomial produces a
 * plain NTT regardless of which Montgomery domain the twiddle table
 * uses internally, so a single plain uint16_t polynomial can be fed to
 * either path and the two outputs compared directly.
 *
 * Input: a deterministic pseudo-random polynomial of degree 512
 * (fixed-seed LCG) -- not decoded from a real Falcon KAT (that needs
 * codec.c's arithmetic decoder, out of scope for this standalone test),
 * but sized to match a real Falcon-512 polynomial rather than an
 * arbitrary small n.
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
/* SW reference: Falcon's native mq_NTT() (16-bit Montgomery domain).    */
/* Extracted verbatim from tests/pqc/optimized/falcon512/vrfy.c.         */
/* ===================================================================== */

#define Q     12289
#define Q0I   12287
#define R      4091
#define R2    10952

/*
 * Table for NTT, binary case:
 *   GMb[x] = R*(g^rev(x)) mod q
 * where g = 7 (it is a 2048-th primitive root of 1 modulo q)
 * and rev() is the bit-reversal function over 10 bits.
 */
static const uint16_t GMb[N] = {
	 4091,  7888, 11060, 11208,  6960,  4342,  6275,  9759,
	 1591,  6399,  9477,  5266,   586,  5825,  7538,  9710,
	 1134,  6407,  1711,   965,  7099,  7674,  3743,  6442,
	10414,  8100,  1885,  1688,  1364, 10329, 10164,  9180,
	12210,  6240,   997,   117,  4783,  4407,  1549,  7072,
	 2829,  6458,  4431,  8877,  7144,  2564,  5664,  4042,
	12189,   432, 10751,  1237,  7610,  1534,  3983,  7863,
	 2181,  6308,  8720,  6570,  4843,  1690,    14,  3872,
	 5569,  9368, 12163,  2019,  7543,  2315,  4673,  7340,
	 1553,  1156,  8401, 11389,  1020,  2967, 10772,  7045,
	 3316, 11236,  5285, 11578, 10637, 10086,  9493,  6180,
	 9277,  6130,  3323,   883, 10469,   489,  1502,  2851,
	11061,  9729,  2742, 12241,  4970, 10481, 10078,  1195,
	  730,  1762,  3854,  2030,  5892, 10922,  9020,  5274,
	 9179,  3604,  3782, 10206,  3180,  3467,  4668,  2446,
	 7613,  9386,   834,  7703,  6836,  3403,  5351, 12276,
	 3580,  1739, 10820,  9787, 10209,  4070, 12250,  8525,
	10401,  2749,  7338, 10574,  6040,   943,  9330,  1477,
	 6865,  9668,  3585,  6633, 12145,  4063,  3684,  7680,
	 8188,  6902,  3533,  9807,  6090,   727, 10099,  7003,
	 6945,  1949,  9731, 10559,  6057,   378,  7871,  8763,
	 8901,  9229,  8846,  4551,  9589, 11664,  7630,  8821,
	 5680,  4956,  6251,  8388, 10156,  8723,  2341,  3159,
	 1467,  5460,  8553,  7783,  2649,  2320,  9036,  6188,
	  737,  3698,  4699,  5753,  9046,  3687,    16,   914,
	 5186, 10531,  4552,  1964,  3509,  8436,  7516,  5381,
	10733,  3281,  7037,  1060,  2895,  7156,  8887,  5357,
	 6409,  8197,  2962,  6375,  5064,  6634,  5625,   278,
	  932, 10229,  8927,  7642,   351,  9298,   237,  5858,
	 7692,  3146, 12126,  7586,  2053, 11285,  3802,  5204,
	 4602,  1748, 11300,   340,  3711,  4614,   300, 10993,
	 5070, 10049, 11616, 12247,  7421, 10707,  5746,  5654,
	 3835,  5553,  1224,  8476,  9237,  3845,   250, 11209,
	 4225,  6326,  9680, 12254,  4136,  2778,   692,  8808,
	 6410,  6718, 10105, 10418,  3759,  7356, 11361,  8433,
	 6437,  3652,  6342,  8978,  5391,  2272,  6476,  7416,
	 8418, 10824, 11986,  5733,   876,  7030,  2167,  2436,
	 3442,  9217,  8206,  4858,  5964,  2746,  7178,  1434,
	 7389,  8879, 10661, 11457,  4220,  1432, 10832,  4328,
	 8557,  1867,  9454,  2416,  3816,  9076,   686,  5393,
	 2523,  4339,  6115,   619,   937,  2834,  7775,  3279,
	 2363,  7488,  6112,  5056,   824, 10204, 11690,  1113,
	 2727,  9848,   896,  2028,  5075,  2654, 10464,  7884,
	12169,  5434,  3070,  6400,  9132, 11672, 12153,  4520,
	 1273,  9739, 11468,  9937, 10039,  9720,  2262,  9399,
	11192,   315,  4511,  1158,  6061,  6751, 11865,   357,
	 7367,  4550,   983,  8534,  8352, 10126,  7530,  9253,
	 4367,  5221,  3999,  8777,  3161,  6990,  4130, 11652,
	 3374, 11477,  1753,   292,  8681,  2806, 10378, 12188,
	 5800, 11811,  3181,  1988,  1024,  9340,  2477, 10928,
	 4582,  6750,  3619,  5503,  5233,  2463,  8470,  7650,
	 7964,  6395,  1071,  1272,  3474, 11045,  3291, 11344,
	 8502,  9478,  9837,  1253,  1857,  6233,  4720, 11561,
	 6034,  9817,  3339,  1797,  2879,  6242,  5200,  2114,
	 7962,  9353, 11363,  5475,  6084,  9601,  4108,  7323,
	10438,  9471,  1271,   408,  6911,  3079,   360,  8276,
	11535,  9156,  9049, 11539,   850,  8617,   784,  7919,
	 8334, 12170,  1846, 10213, 12184,  7827, 11903,  5600,
	 9779,  1012,   721,  2784,  6676,  6552,  5348,  4424,
	 6816,  8405,  9959,  5150,  2356,  5552,  5267,  1333,
	 8801,  9661,  7308,  5788,  4910,   909, 11613,  4395,
	 8238,  6686,  4302,  3044,  2285, 12249,  1963,  9216,
	 4296, 11918,   695,  4371,  9793,  4884,  2411, 10230,
	 2650,   841,  3890, 10231,  7248,  8505, 11196,  6688
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
 * Compute NTT on a ring element (SW reference).
 */
static void
mq_NTT(uint16_t *a, unsigned logn)
{
	size_t n, t, m;

	n = (size_t)1 << logn;
	t = n;
	for (m = 1; m < n; m <<= 1) {
		size_t ht, i, j1;

		ht = t >> 1;
		for (i = 0, j1 = 0; i < m; i ++, j1 += t) {
			size_t j, j2;
			uint32_t s;

			s = GMb[m + i];
			j2 = j1 + ht;
			for (j = j1; j < j2; j ++) {
				uint32_t u, v;

				u = a[j];
				v = mq_montymul(a[j + ht], s);
				a[j] = (uint16_t)mq_add(u, v);
				a[j + ht] = (uint16_t)mq_sub(u, v);
			}
		}
		t = ht;
	}
}

/* ===================================================================== */
/* HW path: mq_NTT_hw()/fmp_NTT_hw(), extracted verbatim from vrfy.c.    */
/* ===================================================================== */

#define VRF_Q_P0I32   4143984639u   /* -1/12289 mod 2^32 */

/*
 * q=12289 NTT twiddle table in the engine's x2^32-Montgomery domain (see
 * the big comment at the top of this file for provenance).
 */
static const uint32_t GM32[N] = {
	4294942718,      11183,      10651,       1669,      12036,       5517,
	     11593,       9397,       7900,       2739,      10901,        589,
	       971,       1704,       4857,       5562,       6241,      10889,
	      7260,       3046,       3102,       8228,        519,       6606,
	     10000,       5956,       6332,      11479,        918,       6357,
	      7237,        196,       8614,       3587,      11068,      11665,
	      3165,       1074,       8124,       3246,       9490,      10617,
	       946,       1812,       2862,       6807,       6659,       7117,
	      8726,       9985,         10,       9788,       4473,       8204,
	     11528,       7220,        657,      11417,      10842,       1827,
	      2845,       7372,       8118,      12120,      11262,       7386,
	       672,       1521,        734,       8135,       7848,       5913,
	     12199,      10220,       8447,       4800,       6849,       8754,
	     12187,       3390,      10989,       5616,       4584,       3792,
	       618,       7653,       2623,       3907,       3775,       8270,
	      2759,      11676,       1514,       9681,        182,       1180,
	      2453,       9557,       9954,        256,       6264,       1450,
	     11792,      10012,        203,       6988,      12216,       9655,
	      5443,      11387,       9242,       8739,       8394,       9453,
	       311,       7013,       7618,       1991,      11971,       3340,
	      4457,       7290,       7841,       3977,       8601,      10525,
	      4232,       8262,       9581,      11207,      11931,       1055,
	      6997,      11064,        208,      11882,       5973,       1724,
	     10020,        954,       8750,      11356,      11685,       8508,
	      4350,       5786,       5458,       1491,        768,       7005,
	      4930,       8196,       9583,       8249,       1639,       9141,
	      4387,        219,      11680,       3614,      12116,      10087,
	      5450,       1034,       4563,      10273,       3081,       2420,
	      1684,       4031,      10170,        306,       2111,      11526,
	       270,       6207,      10670,      10435,      11721,       4420,
	     11376,      10826,       3900,       7730,       4465,       7747,
	      3540,      11743,      10450,       4012,        964,      12057,
	      4262,        759,       3613,       2088,       5007,       4914,
	      4011,       3318,       5112,       9376,       4397,      10007,
	      1767,       4164,        878,       4072,        106,       2983,
	      7529,      10732,       9138,       2798,       5855,       4200,
	      6782,       9535,        588,       2867,       9859,       5582,
	      6867,       6710,       3222,       2794,       9738,        206,
	     10417,       3663,      11025,       1528,       8132,       3703,
	      9062,       4601,       5436,       9451,       8397,       5016,
	        34,      11159,       9371,       2283,       4786,      12259,
	     10689,       6912,       9827,       3754,      11782,        224,
	      5481,       4341,      10318,       2616,       8221,       7251,
	      5761,       8047,      12181,      12264,       2763,       5760,
	      6141,      11321,       5722,       4283,      10712,       9762,
	      4502,       2180,      10873,       5134,      11648,       1786,
	      4530,       9924,        853,       4180,      10729,       9197,
	      3043,       9466,       8115,       4268,      10521,       9604,
	      4260,       3717,       1616,       6291,       7617,       3470,
	      4828,      11586,      10317,       4095,       9487,       2765,
	      5059,       1740,       6777,       4641,       9748,       9994,
	       490,        341,      10264,       8748,      11867,       9688,
	      7615,       6428,       2831,       3500,       4226,       4847,
	      4534,       4008,      11122,       5533,       8350,        795,
	     11388,       5367,       3593,       7090,       7879,       9220,
	      8366,       1709,       3798,      11120,       7291,       6353,
	     10034,       4826,       3414,       1473,       5704,       6327,
	      5637,       7108,        640,      11982,         12,       6830,
	       452,       7387,       8918,       8664,       9596,       1311,
	      8475,        255,      12000,       9605,        225,      11317,
	      9947,      10609,       8712,       6113,       8638,       4958,
	     10454,      10385,       5769,       8504,       2950,      11834,
	      4612,      11536,       8996,       3903,       9480,        829,
	      3250,      10538,       3623,      11876,      10744,      11590,
	      2487,       8427,       7036,       2539,      11050,       1420,
	     10192,       4635,      10030,      10742,      11709,       9879,
	     10924,       3439,       7271,      11355,       4237,        867,
	      9373,      11614,        765,      11442,       8079,       8356,
	      2585,      10953,       6577,       5505,       6050,      10731,
	      7026,       5040,       3812,       2703,       8981,       1510,
	      2385,      11817,       3501,       7979,       8782,        895,
	      6770,       2705,       5127,      11769,        941,       9207,
	      6692,       7466,       9035,       7667,       4419,       2047,
	      6765,      10100,       9872,      10933,       1414,      10113,
	      8201,      12253,      10369,        921,      12214,        324,
	      4991,       4000,      11852,       7295,      12204,       2825,
	      4708,       4731,       6540,      11072,        560,       7412,
	      6155,       2904,       5194,      10988,        251,       9730,
	      5358,       1923,       4248,       9176,        515,        233,
	      4234,       5304,       3820,       3160,       4680,       9276,
	     10410,       1727,      10180,      10094,       6584,       7441,
	     11798,       1138,       5220,       9401,       1634,       4247,
	      8295,       8406,       5916,          4,       1666,       6075,
	      4486,       1266,       1023,      10819,       7623,       6885,
	      2252,      11900,      12024,      10976,      10500,       3796,
	      1733,       5294
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
 * uint16_t-interface dispatcher, drop-in replacement for mq_NTT() above
 * -- plain-domain in, plain-domain out (see the big comment at the top
 * of this file).
 */
static void
mq_NTT_hw(uint16_t *a, unsigned logn)
{
	size_t n = (size_t)1 << logn;
	uint32_t tmp[N];

	for (size_t i = 0; i < n; i++) {
		tmp[i] = a[i];
	}
	fmp_NTT_hw(logn, tmp, GM32, Q, VRF_Q_P0I32, 0);
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

	print_uart("=== ntt: Falcon forward NTT mod 12289, n=");
	print_uart_dec((int)N);
	print_uart(" ===\n");

	gen_poly(a_sw, N, 0xC0FFEEu);
	memcpy(a_hw, a_sw, sizeof a_sw);

	clear_csr(mcountinhibit, 1);

	write_csr(mcycle, 0);
	mq_NTT(a_sw, LOGN);
	cycles_sw = (uint32_t)read_csr(mcycle);
	print_uart("SW cycles: ");
	print_uart_dec((int)cycles_sw);
	print_uart("\n");

	write_csr(mcycle, 0);
	mq_NTT_hw(a_hw, LOGN);
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
