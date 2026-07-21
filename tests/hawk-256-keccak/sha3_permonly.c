/*
 * SHA3/SHAKE implementation -- "permutation-only" hardware offload variant,
 * for comparison against the DMA-absorb-engine sha3.c.
 *
 * The sponge absorb/squeeze bookkeeping (byte-XOR into the 1600-bit state,
 * rate-block boundary detection, pad10*1 padding) all happens in plain C,
 * exactly as in the pure-software tests/hawk-256/sha3.c. The Keccak AXI
 * accelerator is used only as a one-shot 24-round permutation function:
 * upload the full 25-word state, pulse CSREG.START, poll DONE, read the
 * 25-word result back. No DMA job engine, no multi-context hardware
 * residency tracking -- every process_block() call is fully self-contained.
 */

#include <stddef.h>
#include <stdint.h>
#include <string.h>

#include "ng_inner.h"
#include "keccak_axi.h"

#define KECCAK_AXI_BASE_ADDR 0x50000000UL

static void
process_block(uint64_t *A)
{
	uint64_t volatile *cryptoState =
	    (uint64_t volatile *)(KECCAK_AXI_BASE_ADDR + KECCAK_DATA_0_REG_OFFSET);
	uint64_t volatile *csreg =
	    (uint64_t volatile *)(KECCAK_AXI_BASE_ADDR + KECCAK_CSREG_REG_OFFSET);
	int i;

	for (i = 0; i < 25; i ++) {
		cryptoState[i] = A[i];
	}

	*csreg |= (uint64_t)1 << KECCAK_CSREG_START_BIT;
	while (((*csreg) & ((uint64_t)1 << KECCAK_CSREG_DONE_BIT)) == 0);
	*csreg = 0;

	for (i = 0; i < 25; i ++) {
		A[i] = cryptoState[i];
	}
}

/* see sha3.h */
void
shake_init(shake_context *sc, unsigned size)
{
	sc->rate = 200 - (size_t)(size >> 2);
	sc->dptr = 0;
	sc->hw_seen = 0;
	memset(sc->A, 0, sizeof sc->A);
}

/* see sha3.h */
void
shake_clone(shake_context *dst, const shake_context *src)
{
	*dst = *src;
}

/* see sha3.h */
void
shake_inject(shake_context *sc, const void *in, size_t len)
{
	size_t dptr, rate;
	const uint8_t *buf;

	dptr = sc->dptr;
	rate = sc->rate;
	buf = in;
	while (len > 0) {
		size_t clen, u;

		clen = rate - dptr;
		if (clen > len) {
			clen = len;
		}
		for (u = 0; u < clen; u ++) {
			size_t v;

			v = u + dptr;
			sc->A[v >> 3] ^= (uint64_t)buf[u] << ((v & 7) << 3);
		}
		dptr += clen;
		buf += clen;
		len -= clen;
		if (dptr == rate) {
			process_block(sc->A);
			dptr = 0;
		}
	}
	sc->dptr = (unsigned)dptr;
}

/* see sha3.h */
void
shake_flip(shake_context *sc)
{
	unsigned v;

	v = (unsigned)sc->dptr;
	sc->A[v >> 3] ^= (uint64_t)0x1F << ((v & 7) << 3);
	v = (unsigned)sc->rate - 1;
	sc->A[v >> 3] ^= (uint64_t)0x80 << ((v & 7) << 3);
	sc->dptr = sc->rate;
}

/* see sha3.h */
void
shake_extract(shake_context *sc, void *out, size_t len)
{
	size_t dptr, rate;
	uint8_t *buf;

	dptr = sc->dptr;
	rate = sc->rate;
	buf = out;
	while (len > 0) {
		size_t clen;

		if (dptr == rate) {
			process_block(sc->A);
			dptr = 0;
		}
		clen = rate - dptr;
		if (clen > len) {
			clen = len;
		}
		len -= clen;
		while (clen -- > 0) {
			*buf ++ = (uint8_t)(sc->A[dptr >> 3]
				>> ((dptr & 7) << 3));
			dptr ++;
		}
	}
	sc->dptr = (unsigned)dptr;
}
