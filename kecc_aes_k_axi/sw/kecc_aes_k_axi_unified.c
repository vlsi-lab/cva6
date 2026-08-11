// kecc_aes_k_axi_unified (v2) Accelerator IP - Loosely, area-optimized
// Bare-metal MMIO driver for the AXI-memory-mapped unified-storage AES/
// Keccak accelerator (kecc_aes_k_axi_unified_top.sv, module name
// `kecc_aes_k_axi_top` -- see that file's header for why). Same public API
// as kecc_aes_k_axi.h/kecc_aes_k_axi.c (the non-unified driver) -- every
// caller (tests/loosely/*'s .c files) is byte-identical regardless of
// which of these two .c files gets linked in; only the register offsets
// and the lack of a separate RESULT bank differ here. See
// kecc_aes_k_axi_unified.hjson for the register map / handshake rationale.

#include "kecc_aes_k_axi.h"
#include "kecc_aes_k_axi_unified_regs.h"

// See kecc_aes_k_axi.c's identical comment -- same RISC-V memory-ordering
// reasoning applies here unchanged.
#define MMIO_FENCE() asm volatile ("fence" ::: "memory")

#define REG64(off) (*(volatile uint64_t *)(KECC_AES_K_AXI_BASE + (off)))

static uint64_t load64le(const uint8_t x[8])
{
  uint64_t r = 0;
  for (int i = 0; i < 8; i++) r |= (uint64_t)x[i] << (8 * i);
  return r;
}

static void store64le(uint8_t x[8], uint64_t u)
{
  for (int i = 0; i < 8; i++) x[i] = (uint8_t)(u >> (8 * i));
}

// See kecc_aes_k_axi.c's identical comment -- same big-endian whole-vector
// convention on the AES side, confirmed by the same aes_key_mem.sv/
// aes_encipher_datapath.sv this driver's core reuses verbatim (see
// kecc_aes_k_axi/hw/rtl/v2_unified.flist).
static uint64_t load64be(const uint8_t x[8])
{
  uint64_t r = 0;
  for (int i = 0; i < 8; i++) r = (r << 8) | x[i];
  return r;
}

static void store64be(uint8_t x[8], uint64_t u)
{
  for (int i = 0; i < 8; i++) x[i] = (uint8_t)(u >> (8 * (7 - i)));
}

static void ctrl_write(uint64_t ctrl)
{
  REG64(KECC_AES_K_AXI_UNIFIED_CTRL_REG_OFFSET) = ctrl;
}

static uint64_t status_read(void)
{
  return REG64(KECC_AES_K_AXI_UNIFIED_STATUS_REG_OFFSET);
}

static void wait_ready(void)
{
  while (!((status_read() >> KECC_AES_K_AXI_UNIFIED_STATUS_READY_BIT) & 1u));
}

static void wait_result_valid(void)
{
  while (!((status_read() >> KECC_AES_K_AXI_UNIFIED_STATUS_RESULT_VALID_BIT) & 1u));
}

static void wait_keccak_done(void)
{
  while (!((status_read() >> KECC_AES_K_AXI_UNIFIED_STATUS_KECCAK_DONE_BIT) & 1u));
}

static void write_key(const uint8_t key[32])
{
  REG64(KECC_AES_K_AXI_UNIFIED_KEY_3_REG_OFFSET) = load64be(key + 0);
  REG64(KECC_AES_K_AXI_UNIFIED_KEY_2_REG_OFFSET) = load64be(key + 8);
  REG64(KECC_AES_K_AXI_UNIFIED_KEY_1_REG_OFFSET) = load64be(key + 16);
  REG64(KECC_AES_K_AXI_UNIFIED_KEY_0_REG_OFFSET) = load64be(key + 24);
}

// BLOCK0/BLOCK1 are 64-bit-wide registers in their own right (each just
// happens to be reggen'd as two hw-writable 32-bit sub-fields, W0/W1 and
// W2/W3, to give the core's AES SBOX phase independent per-word commit --
// see kecc_aes_k_axi_unified.hjson) -- a single 64-bit MMIO write here
// covers both fields of a register at once, same as the non-unified
// driver's BLOCK_0/BLOCK_1 writes.
static void write_block(const uint8_t block[16])
{
  REG64(KECC_AES_K_AXI_UNIFIED_BLOCK1_REG_OFFSET) = load64be(block + 0);
  REG64(KECC_AES_K_AXI_UNIFIED_BLOCK0_REG_OFFSET) = load64be(block + 8);
}

// No RESULT bank in this design -- BLOCK0/BLOCK1 hold the transformed
// value once STATUS.RESULT_VALID is 1 (the core writes its output back
// into the very same registers it read the input from). Read it with the
// same word order/endianness write_block used.
static void read_block(uint8_t block[16])
{
  store64be(block + 0, REG64(KECC_AES_K_AXI_UNIFIED_BLOCK1_REG_OFFSET));
  store64be(block + 8, REG64(KECC_AES_K_AXI_UNIFIED_BLOCK0_REG_OFFSET));
}

static const uint16_t KECCAK_DATA_OFFSET[25] = {
  KECC_AES_K_AXI_UNIFIED_KECCAK_DATA_0_REG_OFFSET,  KECC_AES_K_AXI_UNIFIED_KECCAK_DATA_1_REG_OFFSET,
  KECC_AES_K_AXI_UNIFIED_KECCAK_DATA_2_REG_OFFSET,  KECC_AES_K_AXI_UNIFIED_KECCAK_DATA_3_REG_OFFSET,
  KECC_AES_K_AXI_UNIFIED_KECCAK_DATA_4_REG_OFFSET,  KECC_AES_K_AXI_UNIFIED_KECCAK_DATA_5_REG_OFFSET,
  KECC_AES_K_AXI_UNIFIED_KECCAK_DATA_6_REG_OFFSET,  KECC_AES_K_AXI_UNIFIED_KECCAK_DATA_7_REG_OFFSET,
  KECC_AES_K_AXI_UNIFIED_KECCAK_DATA_8_REG_OFFSET,  KECC_AES_K_AXI_UNIFIED_KECCAK_DATA_9_REG_OFFSET,
  KECC_AES_K_AXI_UNIFIED_KECCAK_DATA_10_REG_OFFSET, KECC_AES_K_AXI_UNIFIED_KECCAK_DATA_11_REG_OFFSET,
  KECC_AES_K_AXI_UNIFIED_KECCAK_DATA_12_REG_OFFSET, KECC_AES_K_AXI_UNIFIED_KECCAK_DATA_13_REG_OFFSET,
  KECC_AES_K_AXI_UNIFIED_KECCAK_DATA_14_REG_OFFSET, KECC_AES_K_AXI_UNIFIED_KECCAK_DATA_15_REG_OFFSET,
  KECC_AES_K_AXI_UNIFIED_KECCAK_DATA_16_REG_OFFSET, KECC_AES_K_AXI_UNIFIED_KECCAK_DATA_17_REG_OFFSET,
  KECC_AES_K_AXI_UNIFIED_KECCAK_DATA_18_REG_OFFSET, KECC_AES_K_AXI_UNIFIED_KECCAK_DATA_19_REG_OFFSET,
  KECC_AES_K_AXI_UNIFIED_KECCAK_DATA_20_REG_OFFSET, KECC_AES_K_AXI_UNIFIED_KECCAK_DATA_21_REG_OFFSET,
  KECC_AES_K_AXI_UNIFIED_KECCAK_DATA_22_REG_OFFSET, KECC_AES_K_AXI_UNIFIED_KECCAK_DATA_23_REG_OFFSET,
  KECC_AES_K_AXI_UNIFIED_KECCAK_DATA_24_REG_OFFSET,
};

// See kecc_aes_k_axi.c's identical comment -- same key-schedule caching
// rationale (the schedule itself is still private, internal-only storage
// in this design too -- see keccak_aes_k_top_unified.sv's header).
static uint8_t g_last_key[32];
static int g_last_keylen256 = -1;
static int g_last_encdec = -1;
static int g_schedule_valid = 0;

static int schedule_matches(const uint8_t key[32], int keylen256, int encdec)
{
  return g_schedule_valid && keylen256 == g_last_keylen256 && encdec == g_last_encdec
      && __builtin_memcmp(key, g_last_key, 32) == 0;
}

static void aes_block_op(const uint8_t key[32], int keylen256, int encdec,
                          const uint8_t block_in[16], uint8_t block_out[16])
{
  const uint64_t ctrl_base = (1u << KECC_AES_K_AXI_UNIFIED_CTRL_SEL_BIT)
                            | ((encdec ? 1u : 0u) << KECC_AES_K_AXI_UNIFIED_CTRL_ENCDEC_BIT)
                            | ((keylen256 ? 1u : 0u) << KECC_AES_K_AXI_UNIFIED_CTRL_KEYLEN_BIT);

  if (!schedule_matches(key, keylen256, encdec)) {
    ctrl_write(ctrl_base);
    write_key(key);
    MMIO_FENCE();

    ctrl_write(ctrl_base | (1u << KECC_AES_K_AXI_UNIFIED_CTRL_INIT_BIT));
    MMIO_FENCE();
    wait_ready();
    ctrl_write(ctrl_base);

    __builtin_memcpy(g_last_key, key, 32);
    g_last_keylen256 = keylen256;
    g_last_encdec = encdec;
    g_schedule_valid = 1;
  } else {
    ctrl_write(ctrl_base);
  }

  write_block(block_in);
  MMIO_FENCE();

  ctrl_write(ctrl_base | (1u << KECC_AES_K_AXI_UNIFIED_CTRL_NEXT_BIT));
  MMIO_FENCE();
  wait_ready();
  wait_result_valid();
  MMIO_FENCE();

  read_block(block_out);
  ctrl_write(ctrl_base);
}

void kecc_aes_k_axi_aes_encrypt_block(const uint8_t key[32], int keylen256,
                                       const uint8_t block_in[16], uint8_t block_out[16])
{
  aes_block_op(key, keylen256, /*encdec=*/1, block_in, block_out);
}

void kecc_aes_k_axi_aes_decrypt_block(const uint8_t key[32], int keylen256,
                                       const uint8_t block_in[16], uint8_t block_out[16])
{
  aes_block_op(key, keylen256, /*encdec=*/0, block_in, block_out);
}

void kecc_aes_k_axi_keccak_permute(const uint8_t state_in[200], uint8_t state_out[200])
{
  const uint64_t ctrl_base = 0; // SEL = 0 (keccak); encdec/keylen don't-care

  // BLOCK0/BLOCK1 alias two of the core's 25 Keccak "lanes" only in the
  // non-unified design's internal state_reg -- this design has no such
  // aliasing (BLOCK and KECCAK_DATA are always genuinely separate register
  // file locations), so a Keccak call could not disturb AES state even if
  // it wanted to. Still invalidate the cached schedule defensively, for
  // the same reason the non-unified driver does: nothing currently
  // interleaves Keccak and AES calls on one instance, but a future caller
  // might, and cache invalidation on the safe side is free.
  g_schedule_valid = 0;

  ctrl_write(ctrl_base);
  for (int i = 0; i < 25; i++) {
    REG64(KECCAK_DATA_OFFSET[i]) = load64le(state_in + 8 * i);
  }
  MMIO_FENCE();

  ctrl_write(ctrl_base | (1u << KECC_AES_K_AXI_UNIFIED_CTRL_NEXT_BIT));
  MMIO_FENCE();
  wait_ready();
  wait_keccak_done();
  MMIO_FENCE();

  for (int i = 0; i < 25; i++) {
    store64le(state_out + 8 * i, REG64(KECCAK_DATA_OFFSET[i]));
  }

  ctrl_write(ctrl_base);
  REG64(KECC_AES_K_AXI_UNIFIED_STATUS_REG_OFFSET) = 0;
}

void kecc_aes_k_axi_zeroize(void)
{
  ctrl_write(1u << KECC_AES_K_AXI_UNIFIED_CTRL_ZEROIZE_BIT);
  MMIO_FENCE();

  ctrl_write(0);
  MMIO_FENCE();
  wait_ready();

  g_schedule_valid = 0;
}
