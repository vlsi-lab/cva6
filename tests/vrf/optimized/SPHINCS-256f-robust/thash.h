#ifndef SPX_THASH_H
#define SPX_THASH_H

#include "context.h"
#include "params.h"

#include <stdint.h>

#define thash SPX_NAMESPACE(thash)
void thash(unsigned char *out, const unsigned char *in, unsigned int inblocks,
           const spx_ctx *ctx, uint32_t addr[8]);

/* 1 if this build links thash_shake_robust.c (bitmask construction), 0 for
 * thash_shake_simple.c -- defined by whichever of those two files is
 * actually compiled in, so callers outside thash_shake_*.c (wots.c's
 * HW-dispatched gen_chain(), see CA_CTRL_GO's ROBUST bit) can pick the
 * correct chain_job_ctrl construction without wots.c itself differing
 * between the "simple" and "robust" variants. */
extern const int spx_thash_robust;

#endif
