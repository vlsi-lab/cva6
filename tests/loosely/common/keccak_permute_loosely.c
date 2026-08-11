// Loosely-coupled AXI accelerator-backed KeccakF1600_StatePermute -- the C
// analogue of tests/tightly/common/keccak_permute.s (coprocessor-instruction
// asm) and tests/software/common/fips202.c's own static implementation.
// fips202.c declares `extern void KeccakF1600_StatePermute(uint64_t
// state[25]);` when built with -DUSE_COPROCESSOR_ASM (see fips202.c's
// #ifndef USE_COPROCESSOR_ASM guard); this file provides that symbol so
// fips202.c itself, and everything built on it (kmac.c, hmac.c, sha3_*,
// shake*, the keccak_sponge_* tests), is byte-identical across all three
// trees -- only which primitive file gets linked differs.

#include <stdint.h>
#include "kecc_aes_k_axi.h"

void KeccakF1600_StatePermute(uint64_t state[25])
{
  // kecc_aes_k_axi_keccak_permute's state_in/state_out are little-endian
  // within each 64-bit lane, same convention as this uint64_t[25] array on a
  // little-endian RISC-V target -- a direct cast, no repacking. In-place
  // aliasing (state_in == state_out) is explicitly supported.
  kecc_aes_k_axi_keccak_permute((const uint8_t *)state, (uint8_t *)state);
}
