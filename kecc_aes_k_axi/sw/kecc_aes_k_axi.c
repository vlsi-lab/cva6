// kecc_aes_k_axi (v2) Accelerator IP - Loosely
// Bare-metal MMIO driver for the AXI-memory-mapped unified AES/Keccak
// accelerator (kecc_aes_k_axi_top.sv). See kecc_aes_k_axi.h for the public
// API and kecc_aes_k_axi.hjson for the register map / handshake rationale.

#include "kecc_aes_k_axi.h"
#include "kecc_aes_k_axi_regs.h"

// RISC-V's memory model does not guarantee that MMIO writes/reads to
// *different* addresses complete in program order without an explicit
// fence (same reasoning as the sibling keccak-only IP's
// tests/keccak64/keccak_axi.c): fence before pulsing INIT/NEXT (so the
// core samples fully-written KEY/BLOCK/KECCAK_DATA), and fence before
// reading RESULT/KECCAK_DATA back (so the core's completed write is
// visible).
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

// The AES side of the vendored core treats key[255:0]/block[127:0]/result[127:0]
// as plain big-endian whole-vector numbers (byte 0 of the logical array is the
// MOST significant byte of the vector) -- confirmed against aes_key_mem.sv /
// aes_encipher_datapath.sv and the known-good kecc-aes-k v2 testbench's own KAT
// packing convention. This is the opposite convention from the Keccak side
// (load64le/store64le above, confirmed correct by the passing keccak_core KAT) --
// do not reuse load64le/store64le for AES key/block/result.
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
  REG64(KECC_AES_K_AXI_CTRL_REG_OFFSET) = ctrl;
}

static uint64_t status_read(void)
{
  return REG64(KECC_AES_K_AXI_STATUS_REG_OFFSET);
}

static void wait_ready(void)
{
  while (!((status_read() >> KECC_AES_K_AXI_STATUS_READY_BIT) & 1u));
}

static void wait_result_valid(void)
{
  while (!((status_read() >> KECC_AES_K_AXI_STATUS_RESULT_VALID_BIT) & 1u));
}

static void wait_keccak_done(void)
{
  while (!((status_read() >> KECC_AES_K_AXI_STATUS_KECCAK_DONE_BIT) & 1u));
}

// AES key/block/result staging registers -- word i = bits[64*i +: 64] of
// the respective port, little-endian within each 64-bit word (byte 0 of
// word i is the LSB), same convention as tests/tightly/common/
// aes128_block.c's load64le/store64le.
static void write_key(const uint8_t key[32])
{
  // key[255:0] big-endian: key[0..7] is the top word (KEY_3) ... key[24..31] is
  // the bottom word (KEY_0). For a 128-bit key the caller's real 16 bytes live
  // at key[0..15], landing in KEY_3/KEY_2 (the upper half) -- the half
  // aes_key_mem.sv's round==0 branch actually reads for AES-128.
  REG64(KECC_AES_K_AXI_KEY_3_REG_OFFSET) = load64be(key + 0);
  REG64(KECC_AES_K_AXI_KEY_2_REG_OFFSET) = load64be(key + 8);
  REG64(KECC_AES_K_AXI_KEY_1_REG_OFFSET) = load64be(key + 16);
  REG64(KECC_AES_K_AXI_KEY_0_REG_OFFSET) = load64be(key + 24);
}

static void write_block(const uint8_t block[16])
{
  REG64(KECC_AES_K_AXI_BLOCK_1_REG_OFFSET) = load64be(block + 0);
  REG64(KECC_AES_K_AXI_BLOCK_0_REG_OFFSET) = load64be(block + 8);
}

static void read_result(uint8_t block[16])
{
  store64be(block + 0, REG64(KECC_AES_K_AXI_RESULT_1_REG_OFFSET));
  store64be(block + 8, REG64(KECC_AES_K_AXI_RESULT_0_REG_OFFSET));
}

static const uint16_t KECCAK_DATA_OFFSET[25] = {
  KECC_AES_K_AXI_KECCAK_DATA_0_REG_OFFSET,  KECC_AES_K_AXI_KECCAK_DATA_1_REG_OFFSET,
  KECC_AES_K_AXI_KECCAK_DATA_2_REG_OFFSET,  KECC_AES_K_AXI_KECCAK_DATA_3_REG_OFFSET,
  KECC_AES_K_AXI_KECCAK_DATA_4_REG_OFFSET,  KECC_AES_K_AXI_KECCAK_DATA_5_REG_OFFSET,
  KECC_AES_K_AXI_KECCAK_DATA_6_REG_OFFSET,  KECC_AES_K_AXI_KECCAK_DATA_7_REG_OFFSET,
  KECC_AES_K_AXI_KECCAK_DATA_8_REG_OFFSET,  KECC_AES_K_AXI_KECCAK_DATA_9_REG_OFFSET,
  KECC_AES_K_AXI_KECCAK_DATA_10_REG_OFFSET, KECC_AES_K_AXI_KECCAK_DATA_11_REG_OFFSET,
  KECC_AES_K_AXI_KECCAK_DATA_12_REG_OFFSET, KECC_AES_K_AXI_KECCAK_DATA_13_REG_OFFSET,
  KECC_AES_K_AXI_KECCAK_DATA_14_REG_OFFSET, KECC_AES_K_AXI_KECCAK_DATA_15_REG_OFFSET,
  KECC_AES_K_AXI_KECCAK_DATA_16_REG_OFFSET, KECC_AES_K_AXI_KECCAK_DATA_17_REG_OFFSET,
  KECC_AES_K_AXI_KECCAK_DATA_18_REG_OFFSET, KECC_AES_K_AXI_KECCAK_DATA_19_REG_OFFSET,
  KECC_AES_K_AXI_KECCAK_DATA_20_REG_OFFSET, KECC_AES_K_AXI_KECCAK_DATA_21_REG_OFFSET,
  KECC_AES_K_AXI_KECCAK_DATA_22_REG_OFFSET, KECC_AES_K_AXI_KECCAK_DATA_23_REG_OFFSET,
  KECC_AES_K_AXI_KECCAK_DATA_24_REG_OFFSET,
};

static void aes_block_op(const uint8_t key[32], int keylen256, int encdec,
                          const uint8_t block_in[16], uint8_t block_out[16])
{
  const uint64_t ctrl_base = (1u << KECC_AES_K_AXI_CTRL_SEL_BIT)
                            | ((encdec ? 1u : 0u) << KECC_AES_K_AXI_CTRL_ENCDEC_BIT)
                            | ((keylen256 ? 1u : 0u) << KECC_AES_K_AXI_CTRL_KEYLEN_BIT);

  // 1. set sel/encdec/keylen, write key, pulse init, poll ready.
  ctrl_write(ctrl_base);
  write_key(key);
  MMIO_FENCE(); // key must be visible before init pulses the key schedule

  ctrl_write(ctrl_base | (1u << KECC_AES_K_AXI_CTRL_INIT_BIT));
  MMIO_FENCE(); // init write must be visible before we start polling
  wait_ready();
  ctrl_write(ctrl_base); // clear INIT, re-arm for the next pulse

  // 2. write block, pulse next, poll ready/result_valid, read result.
  write_block(block_in);
  MMIO_FENCE(); // block must be visible before next pulses the round pipeline

  ctrl_write(ctrl_base | (1u << KECC_AES_K_AXI_CTRL_NEXT_BIT));
  MMIO_FENCE(); // next write must be visible before we start polling
  wait_ready();
  wait_result_valid();
  MMIO_FENCE(); // result must be visible before it is read back

  read_result(block_out);
  ctrl_write(ctrl_base); // clear NEXT, re-arm for the next pulse
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

  // 1. set sel, write keccak_din.
  ctrl_write(ctrl_base);
  for (int i = 0; i < 25; i++) {
    REG64(KECCAK_DATA_OFFSET[i]) = load64le(state_in + 8 * i);
  }
  MMIO_FENCE(); // all state must be visible before next reads it (state_load_din)

  // 2. pulse next, poll ready/keccak_done, read keccak_dout.
  ctrl_write(ctrl_base | (1u << KECC_AES_K_AXI_CTRL_NEXT_BIT));
  MMIO_FENCE(); // next write must be visible before we start polling
  wait_ready();
  wait_keccak_done();
  MMIO_FENCE(); // the permuted state must be visible before it is read back

  for (int i = 0; i < 25; i++) {
    store64le(state_out + 8 * i, REG64(KECCAK_DATA_OFFSET[i]));
  }

  ctrl_write(ctrl_base); // clear NEXT, re-arm for the next pulse
  // Clear KECCAK_DONE (sw-clearable latch) -- READY/RESULT_VALID are
  // hardware-driven (ro) in the same register, so writing 0 to the whole
  // register is a safe way to clear just KECCAK_DONE without a
  // read-modify-write.
  REG64(KECC_AES_K_AXI_STATUS_REG_OFFSET) = 0;
}

void kecc_aes_k_axi_zeroize(void)
{
  ctrl_write(1u << KECC_AES_K_AXI_CTRL_ZEROIZE_BIT);
  MMIO_FENCE(); // zeroize write must be visible before we release it

  ctrl_write(0);
  MMIO_FENCE(); // zeroize release must be visible before we poll ready
  wait_ready();
}
