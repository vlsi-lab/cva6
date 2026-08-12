/*
 * Support functions for signatures (hash-to-point, norm).
 *
 * ==========================(LICENSE BEGIN)============================
 *
 * Copyright (c) 2017-2019  Falcon Project
 *
 * Permission is hereby granted, free of charge, to any person obtaining
 * a copy of this software and associated documentation files (the
 * "Software"), to deal in the Software without restriction, including
 * without limitation the rights to use, copy, modify, merge, publish,
 * distribute, sublicense, and/or sell copies of the Software, and to
 * permit persons to whom the Software is furnished to do so, subject to
 * the following conditions:
 *
 * The above copyright notice and this permission notice shall be
 * included in all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 * EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
 * MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
 * IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
 * CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
 * TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
 * SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 *
 * ===========================(LICENSE END)=============================
 *
 * @author   Thomas Pornin <thomas.pornin@nccgroup.com>
 */

#include "inner.h"
#include "encoding.h"   /* read_csr(mcycle), for the profiling counters below */
#include "vrf_axi.h"

/*
 * Cycle accounting for Zf(hash_to_point_vartime)()/Zf(is_short)() -- added
 * to measure their share of falcon*-opt's crypto_sign_open(), the same
 * "wrap the function body, not each call site" pattern already used for
 * mq_NTT_hw/mq_iNTT_hw's falcon_ntt_dispatch_cycles (vrfy.c). Answers "how
 * much of the still-software 52.9% of verify (after NTT/iNTT hardware) is
 * hash-to-point's rejection-sampling loop, versus everything else".
 */
uint64_t falcon_hash_to_point_cycles = 0;
uint64_t falcon_hash_to_point_calls  = 0;
uint64_t falcon_is_short_cycles = 0;
uint64_t falcon_is_short_calls  = 0;

/* see inner.h */
void
Zf(hash_to_point_vartime)(
	inner_shake256_context *sc,
	uint16_t *x, unsigned logn)
{
	/*
	 * Offloaded to the rej_sampler hardware unit (vrf_ip/rtl/
	 * rej_sampler.sv, dispatched via shake.c's Zf(hash_to_point_hw)())
	 * -- q=12289 and thresh=61445=5*12289 are Falcon's fixed values,
	 * matching what the reference software loop this replaces used
	 * (see git history for that version). Still not constant-time (the
	 * hardware's own squeeze count is exactly as data-dependent as the
	 * software loop was), for the same reasons given in the reference
	 * implementation's original comment.
	 */
	uint64_t _prof_c0 = read_csr(mcycle);

	Zf(hash_to_point_hw)(sc, x, (unsigned)1 << logn, 12289, 61445);

	falcon_hash_to_point_cycles += read_csr(mcycle) - _prof_c0;
	falcon_hash_to_point_calls++;
}

/* see inner.h */
void
Zf(hash_to_point_ct)(
	inner_shake256_context *sc,
	uint16_t *x, unsigned logn, uint8_t *tmp)
{
	/*
	 * Each 16-bit sample is a value in 0..65535. The value is
	 * kept if it falls in 0..61444 (because 61445 = 5*12289)
	 * and rejected otherwise; thus, each sample has probability
	 * about 0.93758 of being selected.
	 *
	 * We want to oversample enough to be sure that we will
	 * have enough values with probability at least 1 - 2^(-256).
	 * Depending on degree N, this leads to the following
	 * required oversampling:
	 *
	 *   logn     n  oversampling
	 *     1      2     65
	 *     2      4     67
	 *     3      8     71
	 *     4     16     77
	 *     5     32     86
	 *     6     64    100
	 *     7    128    122
	 *     8    256    154
	 *     9    512    205
	 *    10   1024    287
	 *
	 * If logn >= 7, then the provided temporary buffer is large
	 * enough. Otherwise, we use a stack buffer of 63 entries
	 * (i.e. 126 bytes) for the values that do not fit in tmp[].
	 */

	static const uint16_t overtab[] = {
		0, /* unused */
		65,
		67,
		71,
		77,
		86,
		100,
		122,
		154,
		205,
		287
	};

	unsigned n, n2, u, m, p, over;
	uint16_t *tt1, tt2[63];

	/*
	 * We first generate m 16-bit value. Values 0..n-1 go to x[].
	 * Values n..2*n-1 go to tt1[]. Values 2*n and later go to tt2[].
	 * We also reduce modulo q the values; rejected values are set
	 * to 0xFFFF.
	 */
	n = 1U << logn;
	n2 = n << 1;
	over = overtab[logn];
	m = n + over;
	tt1 = (uint16_t *)tmp;
	for (u = 0; u < m; u ++) {
		uint8_t buf[2];
		uint32_t w, wr;

		inner_shake256_extract(sc, buf, sizeof buf);
		w = ((uint32_t)buf[0] << 8) | (uint32_t)buf[1];
		wr = w - ((uint32_t)24578 & (((w - 24578) >> 31) - 1));
		wr = wr - ((uint32_t)24578 & (((wr - 24578) >> 31) - 1));
		wr = wr - ((uint32_t)12289 & (((wr - 12289) >> 31) - 1));
		wr |= ((w - 61445) >> 31) - 1;
		if (u < n) {
			x[u] = (uint16_t)wr;
		} else if (u < n2) {
			tt1[u - n] = (uint16_t)wr;
		} else {
			tt2[u - n2] = (uint16_t)wr;
		}
	}

	/*
	 * Now we must "squeeze out" the invalid values. We do this in
	 * a logarithmic sequence of passes; each pass computes where a
	 * value should go, and moves it down by 'p' slots if necessary,
	 * where 'p' uses an increasing powers-of-two scale. It can be
	 * shown that in all cases where the loop decides that a value
	 * has to be moved down by p slots, the destination slot is
	 * "free" (i.e. contains an invalid value).
	 */
	for (p = 1; p <= over; p <<= 1) {
		unsigned v;

		/*
		 * In the loop below:
		 *
		 *   - v contains the index of the final destination of
		 *     the value; it is recomputed dynamically based on
		 *     whether values are valid or not.
		 *
		 *   - u is the index of the value we consider ("source");
		 *     its address is s.
		 *
		 *   - The loop may swap the value with the one at index
		 *     u-p. The address of the swap destination is d.
		 */
		v = 0;
		for (u = 0; u < m; u ++) {
			uint16_t *s, *d;
			unsigned j, sv, dv, mk;

			if (u < n) {
				s = &x[u];
			} else if (u < n2) {
				s = &tt1[u - n];
			} else {
				s = &tt2[u - n2];
			}
			sv = *s;

			/*
			 * The value in sv should ultimately go to
			 * address v, i.e. jump back by u-v slots.
			 */
			j = u - v;

			/*
			 * We increment v for the next iteration, but
			 * only if the source value is valid. The mask
			 * 'mk' is -1 if the value is valid, 0 otherwise,
			 * so we _subtract_ mk.
			 */
			mk = (sv >> 15) - 1U;
			v -= mk;

			/*
			 * In this loop we consider jumps by p slots; if
			 * u < p then there is nothing more to do.
			 */
			if (u < p) {
				continue;
			}

			/*
			 * Destination for the swap: value at address u-p.
			 */
			if ((u - p) < n) {
				d = &x[u - p];
			} else if ((u - p) < n2) {
				d = &tt1[(u - p) - n];
			} else {
				d = &tt2[(u - p) - n2];
			}
			dv = *d;

			/*
			 * The swap should be performed only if the source
			 * is valid AND the jump j has its 'p' bit set.
			 */
			mk &= -(((j & p) + 0x1FF) >> 9);

			*s = (uint16_t)(sv ^ (mk & (sv ^ dv)));
			*d = (uint16_t)(dv ^ (mk & (sv ^ dv)));
		}
	}
}

/*
 * Acceptance bound for the (squared) l2-norm of the signature depends
 * on the degree. This array is indexed by logn (1 to 10). These bounds
 * are _inclusive_ (they are equal to floor(beta^2)).
 */
static const uint32_t l2bound[] = {
	0,    /* unused */
	101498,
	208714,
	428865,
	892039,
	1852696,
	3842630,
	7959734,
	16468416,
	34034726,
	70265242
};

/*
 * HW dispatch for Zf(is_short)(): falcon_normcheck.sv accumulates
 * sum(s1[u]^2) + sum(s2[u]^2) with the reference's own constant-time
 * saturating-overflow trick, then compares against NORMCHECK_BOUND
 * (l2bound[logn], computed here in software and passed in -- the
 * threshold table itself is not replicated in hardware). Both s1[]/s2[]
 * are read-only inputs to the accelerator; the only output is a single
 * pass/fail bit read back over MMIO, so unlike Zf(comp_decode)() there is
 * no DMA write and therefore no D-cache-staleness concern to work around
 * here.
 */
#define VRF_AXI_BASE_ADDR 0x50000000UL

/* see inner.h */
int
Zf(is_short)(
	const int16_t *s1, const int16_t *s2, unsigned logn)
{
	uint64_t volatile *normcheck_s1_addr = (uint64_t volatile *)
	    (VRF_AXI_BASE_ADDR + VRF_NORMCHECK_S1_ADDR_REG_OFFSET);
	uint64_t volatile *normcheck_s2_addr = (uint64_t volatile *)
	    (VRF_AXI_BASE_ADDR + VRF_NORMCHECK_S2_ADDR_REG_OFFSET);
	uint64_t volatile *normcheck_bound = (uint64_t volatile *)
	    (VRF_AXI_BASE_ADDR + VRF_NORMCHECK_BOUND_REG_OFFSET);
	uint64_t volatile *normcheck_ctrl = (uint64_t volatile *)
	    (VRF_AXI_BASE_ADDR + VRF_NORMCHECK_CTRL_REG_OFFSET);
	size_t n = (size_t)1 << logn;
	uint64_t ctrl_val;
	uint64_t _prof_c0 = read_csr(mcycle);
	int _prof_ret;

	__asm__ volatile ("fence" ::: "memory");

	*normcheck_s1_addr = (uint64_t)(uintptr_t)s1;
	*normcheck_s2_addr = (uint64_t)(uintptr_t)s2;
	*normcheck_bound   = (uint64_t)l2bound[logn];
	*normcheck_ctrl = ((uint64_t)1 << VRF_NORMCHECK_CTRL_GO_BIT)
	    | ((uint64_t)n << VRF_NORMCHECK_CTRL_N_OFFSET);

	while (((*normcheck_ctrl) & ((uint64_t)1 << VRF_NORMCHECK_CTRL_DONE_BIT)) == 0);

	ctrl_val = *normcheck_ctrl;
	_prof_ret = (ctrl_val & ((uint64_t)1 << VRF_NORMCHECK_CTRL_PASS_BIT)) != 0;

	*normcheck_ctrl = 0;

	__asm__ volatile ("fence" ::: "memory");

	falcon_is_short_cycles += read_csr(mcycle) - _prof_c0;
	falcon_is_short_calls++;
	return _prof_ret;
}

/* see inner.h */
int
Zf(is_short_half)(
	uint32_t sqn, const int16_t *s2, unsigned logn)
{
	size_t n, u;
	uint32_t ng;

	n = (size_t)1 << logn;
	ng = -(sqn >> 31);
	for (u = 0; u < n; u ++) {
		int32_t z;

		z = s2[u];
		sqn += (uint32_t)(z * z);
		ng |= sqn;
	}
	sqn |= -(ng >> 31);

	return sqn <= l2bound[logn];
}
