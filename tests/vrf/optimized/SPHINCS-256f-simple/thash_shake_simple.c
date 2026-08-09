#include <stdint.h>
#include <string.h>

#include "thash.h"
#include "address.h"
#include "params.h"
#include "utils.h"

#include "fips202.h"
#include "vrf_chain.h"

const int spx_thash_robust = 0;

/*
 * THASH1 (F, inblocks=1) and THASH2 (H, inblocks=2) are HW-offloaded to the
 * shared vrf_ip chain-job engine (vrf_ip/rtl/chain_job_ctrl.sv); larger
 * multi-block calls (FORS's final root-aggregation hash, inblocks=
 * SPX_FORS_TREES, and WOTS+'s leaf hash, inblocks=SPX_WOTS_LEN) fall back to
 * the original software path -- chain_job_ctrl.sv's CHAIN_IO/CHAIN_IN2
 * registers only hold one or two SPX_N-byte blocks, matching the FIPS 205
 * F/H primitives exactly, not the generalized T_l construction used for
 * those two larger calls. Protocol validated standalone in
 * tests/app-tests/{thash,thash2} before being used here.
 */
static void
thash_hw(unsigned char *out, const unsigned char *in, unsigned int inblocks,
    const spx_ctx *ctx, uint32_t addr[8])
{
	const uint8_t *addr8 = (const uint8_t *)addr;

	ca_load_seed(ctx->pub_seed, SPX_N);
	ca_load_adrs(addr8);

	if (inblocks == 1) {
		ca_load_chain(in, SPX_N);
		CHAIN_REG[CA_CTRL] = CA_CTRL_GO(CA_OP_THASH1, 0, SPX_N, 1,
		    addr8[SPX_OFFSET_HASH_ADDR]);
	} else {
		ca_load_chain(in, SPX_N);
		ca_load_chain2(in + SPX_N, SPX_N);
		CHAIN_REG[CA_CTRL] = CA_CTRL_GO(CA_OP_THASH2, 0, SPX_N, 1, 0);
	}
	CA_WAIT_POLL;
	ca_read_chain(out, SPX_N);
}

/**
 * Takes an array of inblocks concatenated arrays of SPX_N bytes.
 */
void thash(unsigned char *out, const unsigned char *in, unsigned int inblocks,
           const spx_ctx *ctx, uint32_t addr[8])
{
    if (inblocks == 1 || inblocks == 2) {
        thash_hw(out, in, inblocks, ctx, addr);
        return;
    }

    SPX_VLA(uint8_t, buf, SPX_N + SPX_ADDR_BYTES + inblocks*SPX_N);

    memcpy(buf, ctx->pub_seed, SPX_N);
    memcpy(buf + SPX_N, addr, SPX_ADDR_BYTES);
    memcpy(buf + SPX_N + SPX_ADDR_BYTES, in, inblocks * SPX_N);

    shake256(out, SPX_N, buf, SPX_N + SPX_ADDR_BYTES + inblocks*SPX_N);
}
