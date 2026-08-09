#include <stdint.h>
#include <string.h>

#include "utils.h"
#include "utilsx1.h"
#include "hash.h"
#include "thash.h"
#include "wots.h"
#include "wotsx1.h"
#include "address.h"
#include "params.h"

#include "vrf_chain.h"

// TODO clarify address expectations, and make them more uniform.
// TODO i.e. do we expect types to be set already?
// TODO and do we expect modifications or copies?

/**
 * Computes the chaining function.
 * out and in have to be n-byte arrays.
 *
 * Interprets in as start-th value of the chain.
 * addr has to contain the address of the chain.
 *
 * HW-offloaded: a single chain_job_ctrl (vrf_ip/rtl/chain_job_ctrl.sv)
 * CA_OP_THASH1 job with STEPS>1 runs the whole chain -- its FSM internally
 * loops step_cnt = start..start+steps-1, feeding each step's digest back as
 * the next step's input and overlaying step_cnt into ADRS byte 31
 * (SPX_OFFSET_HASH_ADDR) every step, exactly matching the software loop
 * this replaces. This is the dominant cost in WOTS+ verify (up to
 * SPX_WOTS_W-1 steps per chain, SPX_WOTS_LEN chains per layer, SPX_D
 * layers), so batching the whole chain into one HW job (not one job per
 * step) avoids per-step MMIO/dispatch overhead on top of the per-step
 * arithmetic saving. spx_thash_robust (thash.h, defined by whichever of
 * thash_shake_robust.c/thash_shake_simple.c this build links) selects the
 * bitmask (robust) vs. plain (simple) construction. Protocol validated
 * standalone in tests/app-tests/thash-wots before being used here.
 */
static void gen_chain(unsigned char *out, const unsigned char *in,
                      unsigned int start, unsigned int steps,
                      const spx_ctx *ctx, uint32_t addr[8])
{
    unsigned int clamped_steps = steps;

    if (start + clamped_steps > SPX_WOTS_W) {
        clamped_steps = SPX_WOTS_W - start;
    }

    if (clamped_steps == 0) {
        memcpy(out, in, SPX_N);
        return;
    }

    ca_load_seed(ctx->pub_seed, SPX_N);
    ca_load_adrs((const uint8_t *)addr);
    ca_load_chain(in, SPX_N);

    CHAIN_REG[CA_CTRL] = CA_CTRL_GO(CA_OP_THASH1, spx_thash_robust, SPX_N,
                                    clamped_steps, start);
    CA_WAIT_POLL;

    ca_read_chain(out, SPX_N);
}

/**
 * base_w algorithm as described in draft.
 * Interprets an array of bytes as integers in base w.
 * This only works when log_w is a divisor of 8.
 */
static void base_w(unsigned int *output, const int out_len,
                   const unsigned char *input)
{
    int in = 0;
    int out = 0;
    unsigned char total;
    int bits = 0;
    int consumed;

    for (consumed = 0; consumed < out_len; consumed++) {
        if (bits == 0) {
            total = input[in];
            in++;
            bits += 8;
        }
        bits -= SPX_WOTS_LOGW;
        output[out] = (total >> bits) & (SPX_WOTS_W - 1);
        out++;
    }
}

/* Computes the WOTS+ checksum over a message (in base_w). */
static void wots_checksum(unsigned int *csum_base_w,
                          const unsigned int *msg_base_w)
{
    unsigned int csum = 0;
    unsigned char csum_bytes[(SPX_WOTS_LEN2 * SPX_WOTS_LOGW + 7) / 8];
    unsigned int i;

    /* Compute checksum. */
    for (i = 0; i < SPX_WOTS_LEN1; i++) {
        csum += SPX_WOTS_W - 1 - msg_base_w[i];
    }

    /* Convert checksum to base_w. */
    /* Make sure expected empty zero bits are the least significant bits. */
    csum = csum << ((8 - ((SPX_WOTS_LEN2 * SPX_WOTS_LOGW) % 8)) % 8);
    ull_to_bytes(csum_bytes, sizeof(csum_bytes), csum);
    base_w(csum_base_w, SPX_WOTS_LEN2, csum_bytes);
}

/* Takes a message and derives the matching chain lengths. */
void chain_lengths(unsigned int *lengths, const unsigned char *msg)
{
    base_w(lengths, SPX_WOTS_LEN1, msg);
    wots_checksum(lengths + SPX_WOTS_LEN1, lengths);
}

/**
 * Takes a WOTS signature and an n-byte message, computes a WOTS public key.
 *
 * Writes the computed public key to 'pk'.
 */
void wots_pk_from_sig(unsigned char *pk,
                      const unsigned char *sig, const unsigned char *msg,
                      const spx_ctx *ctx, uint32_t addr[8])
{
    unsigned int lengths[SPX_WOTS_LEN];
    uint32_t i;

    chain_lengths(lengths, msg);

    for (i = 0; i < SPX_WOTS_LEN; i++) {
        set_chain_addr(addr, i);
        gen_chain(pk + i*SPX_N, sig + i*SPX_N,
                  lengths[i], SPX_WOTS_W - 1 - lengths[i], ctx, addr);
    }
}
