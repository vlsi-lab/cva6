/*
 * SHAKE implementation.
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
 *
 * Keccak-f[1600] permutation (process_block) and the Zf(i_shake256_*)
 * state-machine redirected to the Keccak-AXI accelerator
 * (keccak_ip/rtl/keccak_f.sv / keccak_dma_ctrl.sv), following the exact
 * same hardware-resident-state dispatcher pattern used for HAWK
 * (tests/hawk1024-opt/sha3.c) -- see that file's comments for the full
 * rationale. Falcon's SHAKE256-only context (always rate=136, no
 * SHAKE128/size parameter) makes this a direct, simpler port: no `rate`
 * field is needed on inner_shake256_context, only the `hw_seen` flag
 * added in inner.h.
 */

#include <string.h>

#include "inner.h"
#include "keccak_axi.h"

#define KECCAK_AXI_BASE_ADDR 0x50000000UL

/*
 * Fixed SHAKE256 rate in bytes (200-byte state, 64-byte/512-bit capacity).
 * Falcon's inner_shake256_context is SHAKE256-only, unlike HAWK's
 * shake_context (which also serves SHAKE128 via a runtime `rate` field),
 * so this can be a compile-time constant instead of a struct field.
 */
#define SHAKE256_RATE 136

/*
 * Global tracker for which inner_shake256_context, if any, currently owns
 * the Keccak accelerator's resident 1600-bit state. The DATA[] registers
 * are a single shared physical resource -- only one context's state can
 * live there at a time. Comparing against the caller's own context
 * address (rather than a per-context flag) is what makes this safe under
 * interleaved multi-context usage (e.g. KeyGen's RNG context vs. Sign's
 * per-leaf sampler context vs. Verify's hash-to-point context): a
 * per-context flag cannot detect that some *other* context evicted it in
 * between calls.
 */
static inner_shake256_context *hw_owner = NULL;

/*
 * Legacy raw-permute path: pulse the permutation and read the rate-word
 * result back. Callers must have already ensured the accelerator's
 * resident state equals sc->st.A (see keccak_hw_upload_resident() /
 * keccak_hw_prepare_for_absorb()) -- this issues no register writes of
 * its own.
 *
 * Only the rate words (SHAKE256_RATE/8 = 17) are read back, not the full
 * 25-word state: the capacity words are never exposed to a caller of
 * Zf(i_shake256_extract)(), and as long as sc stays hardware-resident
 * (hw_owner == sc) across the next block, the accelerator's own DATA[]
 * registers already hold the correct post-permutation capacity for the
 * next call to consume.
 */
static void
process_block_resident(inner_shake256_context *sc)
{
	uint64_t volatile *cryptoState =
	    (uint64_t volatile *)(KECCAK_AXI_BASE_ADDR + KECCAK_DATA_0_REG_OFFSET);
	uint64_t volatile *csreg =
	    (uint64_t volatile *)(KECCAK_AXI_BASE_ADDR + KECCAK_CSREG_REG_OFFSET);
	size_t i;

	*csreg |= (uint64_t)1 << KECCAK_CSREG_START_BIT;
	while (((*csreg) & ((uint64_t)1 << KECCAK_CSREG_DONE_BIT)) == 0);
	/* explicit zero write: genuinely clears START/DONE */
	*csreg = 0;

	for (i = 0; i < (SHAKE256_RATE >> 3); i ++) {
		sc->st.A[i] = cryptoState[i];
	}
}

/*
 * Make sc the accelerator's resident context via a plain 25-word upload,
 * evicting (saving back to its own memory) whichever other context was
 * resident, if any.
 */
static void
keccak_hw_upload_resident(inner_shake256_context *sc)
{
	uint64_t volatile *cryptoState =
	    (uint64_t volatile *)(KECCAK_AXI_BASE_ADDR + KECCAK_DATA_0_REG_OFFSET);
	int i;

	/*
	 * hw_owner == sc alone is not a safe residency check: C stack
	 * storage gets reused across function calls, so a *different*
	 * logical inner_shake256_context can land at the same address as
	 * a stale hw_owner. sc->hw_seen (reset by every
	 * Zf(i_shake256_init)()) is the true discriminator -- pointer
	 * equality is only trusted once hw_seen already confirms this
	 * exact logical context is the one that set hw_owner.
	 */
	if (hw_owner == sc && sc->hw_seen) {
		return;
	}
	if (hw_owner != NULL && hw_owner != sc) {
		for (i = 0; i < 25; i ++) {
			hw_owner->st.A[i] = cryptoState[i];
		}
	}
	for (i = 0; i < 25; i ++) {
		cryptoState[i] = sc->st.A[i];
	}
	hw_owner = sc;
	sc->hw_seen = 1;
}

/*
 * Make sc the accelerator's resident context in preparation for a
 * hardware absorb job, evicting whichever other context was resident.
 * Unlike keccak_hw_upload_resident(), a context's very first-ever
 * hardware touch can skip the 25-word upload entirely: sc->st.A is
 * guaranteed to be the pristine all-zero state Zf(i_shake256_init)()
 * left it in, and the absorb job's FRESH bit lets hardware zero its own
 * state instead. Returns 1 if the caller's job should set FRESH.
 */
static int
keccak_hw_prepare_for_absorb(inner_shake256_context *sc)
{
	uint64_t volatile *cryptoState =
	    (uint64_t volatile *)(KECCAK_AXI_BASE_ADDR + KECCAK_DATA_0_REG_OFFSET);
	int i;

	if (hw_owner == sc && sc->hw_seen) {
		return 0;
	}
	if (hw_owner != NULL && hw_owner != sc) {
		for (i = 0; i < 25; i ++) {
			hw_owner->st.A[i] = cryptoState[i];
		}
	}
	hw_owner = sc;
	if (!sc->hw_seen) {
		sc->hw_seen = 1;
		return 1;
	}
	for (i = 0; i < 25; i ++) {
		cryptoState[i] = sc->st.A[i];
	}
	return 0;
}

/*
 * Issue one DMA absorb job: hardware reads len raw bytes directly out of
 * CVA6 memory starting at in, XOR-absorbing them into the resident state
 * and autonomously chaining the permutation across as many rate-block
 * boundaries as the job spans -- no CPU round trip per block. If flip is
 * set, SHAKE pad10*1 padding is applied after the absorb without forcing
 * an extra permutation.
 */
static void
keccak_dma_absorb_job(const void *in, uint32_t len, int fresh, int flip,
    unsigned dptr)
{
	uint64_t volatile *job_src_addr =
	    (uint64_t volatile *)(KECCAK_AXI_BASE_ADDR + KECCAK_JOB_SRC_ADDR_REG_OFFSET);
	uint64_t volatile *job_src_len =
	    (uint64_t volatile *)(KECCAK_AXI_BASE_ADDR + KECCAK_JOB_SRC_LEN_REG_OFFSET);
	uint64_t volatile *jobctrl =
	    (uint64_t volatile *)(KECCAK_AXI_BASE_ADDR + KECCAK_JOBCTRL_REG_OFFSET);
	uint64_t ctrl;

	/*
	 * Ensure the CPU's stores into *in (and, on a fresh/uploaded
	 * context switch, into the DATA[] registers above) have reached
	 * memory before the accelerator's AXI master reads them.
	 */
	__asm__ volatile ("fence" ::: "memory");

	*job_src_addr = (uint64_t)(uintptr_t)in;
	*job_src_len  = len;

	ctrl = (uint64_t)1 << KECCAK_JOBCTRL_GO_BIT;
	if (fresh) {
		ctrl |= (uint64_t)1 << KECCAK_JOBCTRL_FRESH_BIT;
	}
	if (flip) {
		ctrl |= (uint64_t)1 << KECCAK_JOBCTRL_FLIP_BIT;
	}
	ctrl |= ((uint64_t)(dptr & KECCAK_JOBCTRL_DPTR_MASK))
	    << KECCAK_JOBCTRL_DPTR_OFFSET;

	*jobctrl = ctrl;
	while (((*jobctrl) & ((uint64_t)1 << KECCAK_JOBCTRL_DONE_BIT)) == 0);
	/* explicit zero write: genuinely clears GO/FRESH/FLIP/DONE */
	*jobctrl = 0;
}

/* see inner.h */
void
Zf(i_shake256_init)(inner_shake256_context *sc)
{
	sc->dptr = 0;
	sc->hw_seen = 0;
	memset(sc->st.A, 0, sizeof sc->st.A);
}

/* see inner.h */
void
Zf(i_shake256_inject)(inner_shake256_context *sc, const uint8_t *in, size_t len)
{
	int fresh;

	if (len == 0) {
		return;
	}

	fresh = keccak_hw_prepare_for_absorb(sc);
	keccak_dma_absorb_job(in, (uint32_t)len, fresh, 0, (unsigned)sc->dptr);
	sc->dptr = (sc->dptr + len) % SHAKE256_RATE;
}

/* see falcon.h */
void
Zf(i_shake256_flip)(inner_shake256_context *sc)
{
	/*
	 * We apply padding and pre-XOR the value into the state. We
	 * set dptr to the end of the buffer, so that the first call to
	 * Zf(i_shake256_extract)() will process the block.
	 */
	if (hw_owner == sc && sc->hw_seen) {
		/* padding applied directly to the resident state; residency
		 * is preserved (no eviction needed), saving a re-upload on
		 * the extract() call that follows */
		keccak_dma_absorb_job(NULL, 0, 0, 1, (unsigned)sc->dptr);
	} else {
		unsigned v;

		v = (unsigned)sc->dptr;
		sc->st.A[v >> 3] ^= (uint64_t)0x1F << ((v & 7) << 3);
		sc->st.A[16] ^= (uint64_t)0x80 << 56;
	}
	sc->dptr = SHAKE256_RATE;
}

/*
 * Non-cacheable DRAM scratch window for the rejection-sampler hardware's
 * output, same convention/rationale as vrfy.c's FALCON_NTT_HW_SCRATCH_ADDR
 * (this SoC's DcacheFlushOnFence/DcacheInvalidateOnFlush are both 0, so an
 * accelerator DMA-writing straight into cacheable memory could leave a
 * stale D$ line masking the write). Same literal address as
 * falcon512-opt's (independent simulations, never resident at once).
 */
#define KECCAK_REJ_HW_SCRATCH_ADDR 0x80F0A000UL
#define KECCAK_REJ_HW_SCRATCH_SIZE 2048u   /* n*2, n<=1024 */

/* see inner.h */
void
Zf(hash_to_point_hw)(inner_shake256_context *sc, uint16_t *x, unsigned n,
	uint32_t q, uint32_t thresh)
{
	uint64_t volatile *rej_x_addr =
	    (uint64_t volatile *)(KECCAK_AXI_BASE_ADDR + KECCAK_REJ_X_ADDR_REG_OFFSET);
	uint64_t volatile *rej_params =
	    (uint64_t volatile *)(KECCAK_AXI_BASE_ADDR + KECCAK_REJ_PARAMS_REG_OFFSET);
	uint64_t volatile *rej_ctrl =
	    (uint64_t volatile *)(KECCAK_AXI_BASE_ADDR + KECCAK_REJ_CTRL_REG_OFFSET);
	uint16_t volatile *scratch = (uint16_t volatile *)KECCAK_REJ_HW_SCRATCH_ADDR;
	unsigned i;

	/*
	 * Idempotent safety net matching Zf(i_shake256_extract)()'s own
	 * pattern: a no-op if sc is already resident (true by construction
	 * at this function's only call site, common.c's
	 * Zf(hash_to_point_vartime)(), reached right after
	 * Zf(i_shake256_flip)()), otherwise uploads/evicts as needed.
	 */
	keccak_hw_upload_resident(sc);

	/*
	 * Ensure the CPU's DATA[]/scratch-adjacent stores above have
	 * reached memory before the accelerator's AXI master reads/writes
	 * them -- ordinary MMIO/DMA ordering, same as every other job
	 * dispatch in this file.
	 */
	__asm__ volatile ("fence" ::: "memory");

	*rej_x_addr = (uint64_t)KECCAK_REJ_HW_SCRATCH_ADDR;
	*rej_params = ((uint64_t)q & KECCAK_REJ_PARAMS_Q_MASK)
	    | (((uint64_t)thresh & KECCAK_REJ_PARAMS_THRESH_MASK)
	        << KECCAK_REJ_PARAMS_THRESH_OFFSET)
	    | ((uint64_t)n << KECCAK_REJ_PARAMS_N_OFFSET);

	*rej_ctrl = (uint64_t)1 << KECCAK_REJ_CTRL_GO_BIT;
	while (((*rej_ctrl) & ((uint64_t)1 << KECCAK_REJ_CTRL_DONE_BIT)) == 0);
	*rej_ctrl = 0;

	for (i = 0; i < n; i ++) {
		x[i] = scratch[i];
	}

	/*
	 * sc->dptr is left stale: the hardware job squeezed and permuted an
	 * unpredictable, rejection-count-dependent number of internal rate
	 * blocks that software never tracked step by step. Safe here
	 * because this function's only call site (common.c's
	 * Zf(hash_to_point_vartime)(), itself only called from nist.c) never
	 * uses sc again afterward -- a future caller that does would need
	 * to call Zf(i_shake256_flip)() again first.
	 */
}

/* see falcon.h */
void
Zf(i_shake256_extract)(inner_shake256_context *sc, uint8_t *out, size_t len)
{
	size_t dptr;
	uint8_t *buf;

	dptr = (size_t)sc->dptr;
	buf = out;
	while (len > 0) {
		size_t clen;

		if (dptr == SHAKE256_RATE) {
			keccak_hw_upload_resident(sc);
			process_block_resident(sc);
			dptr = 0;
		}
		clen = SHAKE256_RATE - dptr;
		if (clen > len) {
			clen = len;
		}
		len -= clen;
		while (clen -- > 0) {
			*buf ++ = (uint8_t)(sc->st.A[dptr >> 3]
				>> ((dptr & 7) << 3));
			dptr ++;
		}
	}
	sc->dptr = dptr;
}
