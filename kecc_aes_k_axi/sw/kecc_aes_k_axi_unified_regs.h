// Generated register defines for kecc_aes_k_axi_unified

#ifndef _KECC_AES_K_AXI_UNIFIED_REG_DEFS_
#define _KECC_AES_K_AXI_UNIFIED_REG_DEFS_

#ifdef __cplusplus
extern "C" {
#endif
// Register width
#define KECC_AES_K_AXI_UNIFIED_PARAM_REG_WIDTH 64

// Control register for the kecc_aes_k_axi_unified accelerator wrapper
#define KECC_AES_K_AXI_UNIFIED_CTRL_REG_OFFSET 0x0
#define KECC_AES_K_AXI_UNIFIED_CTRL_ZEROIZE_BIT 0
#define KECC_AES_K_AXI_UNIFIED_CTRL_SEL_BIT 1
#define KECC_AES_K_AXI_UNIFIED_CTRL_ENCDEC_BIT 2
#define KECC_AES_K_AXI_UNIFIED_CTRL_KEYLEN_BIT 3
#define KECC_AES_K_AXI_UNIFIED_CTRL_INIT_BIT 4
#define KECC_AES_K_AXI_UNIFIED_CTRL_NEXT_BIT 5

// Status register for the kecc_aes_k_axi_unified accelerator wrapper
#define KECC_AES_K_AXI_UNIFIED_STATUS_REG_OFFSET 0x8
#define KECC_AES_K_AXI_UNIFIED_STATUS_READY_BIT 0
#define KECC_AES_K_AXI_UNIFIED_STATUS_RESULT_VALID_BIT 1
#define KECC_AES_K_AXI_UNIFIED_STATUS_KECCAK_DONE_BIT 2

// Word i (0-3) of the 256-bit AES key input, word i = key[64*i +: 64]. AES
// only. Software-owned staging register, read directly by the core -- do not
// write while an operation is in flight. (common parameters)
#define KECC_AES_K_AXI_UNIFIED_KEY_KEY_FIELD_WIDTH 64
#define KECC_AES_K_AXI_UNIFIED_KEY_KEY_FIELDS_PER_REG 1
#define KECC_AES_K_AXI_UNIFIED_KEY_MULTIREG_COUNT 4

// Word i (0-3) of the 256-bit AES key input, word i = key[64*i +: 64]. AES
// only. Software-owned staging register, read directly by the core -- do not
// write while an operation is in flight.
#define KECC_AES_K_AXI_UNIFIED_KEY_0_REG_OFFSET 0x10

// Word i (0-3) of the 256-bit AES key input, word i = key[64*i +: 64]. AES
// only. Software-owned staging register, read directly by the core -- do not
// write while an operation is in flight.
#define KECC_AES_K_AXI_UNIFIED_KEY_1_REG_OFFSET 0x18

// Word i (0-3) of the 256-bit AES key input, word i = key[64*i +: 64]. AES
// only. Software-owned staging register, read directly by the core -- do not
// write while an operation is in flight.
#define KECC_AES_K_AXI_UNIFIED_KEY_2_REG_OFFSET 0x20

// Word i (0-3) of the 256-bit AES key input, word i = key[64*i +: 64]. AES
// only. Software-owned staging register, read directly by the core -- do not
// write while an operation is in flight.
#define KECC_AES_K_AXI_UNIFIED_KEY_3_REG_OFFSET 0x28

// AES only. Upper 64 bits (words 0-1) of the 128-bit AES block -- also the
// core's own round-by-round working register (no separate copy): software
// writes the plaintext/ciphertext here, hardware overwrites it every AES
// sub-step (INIT/SBOX/MAIN/FINAL), and software reads the transformed value
// back from here once STATUS.RESULT_VALID is 1. Do not write while an
// operation is in flight.
#define KECC_AES_K_AXI_UNIFIED_BLOCK1_REG_OFFSET 0x30
#define KECC_AES_K_AXI_UNIFIED_BLOCK1_W1_MASK 0xffffffff
#define KECC_AES_K_AXI_UNIFIED_BLOCK1_W1_OFFSET 0
#define KECC_AES_K_AXI_UNIFIED_BLOCK1_W1_FIELD \
  ((bitfield_field32_t) { .mask = KECC_AES_K_AXI_UNIFIED_BLOCK1_W1_MASK, .index = KECC_AES_K_AXI_UNIFIED_BLOCK1_W1_OFFSET })
#define KECC_AES_K_AXI_UNIFIED_BLOCK1_W0_MASK 0xffffffff
#define KECC_AES_K_AXI_UNIFIED_BLOCK1_W0_OFFSET 32
#define KECC_AES_K_AXI_UNIFIED_BLOCK1_W0_FIELD \
  ((bitfield_field32_t) { .mask = KECC_AES_K_AXI_UNIFIED_BLOCK1_W0_MASK, .index = KECC_AES_K_AXI_UNIFIED_BLOCK1_W0_OFFSET })

// AES only. Lower 64 bits (words 2-3) of the 128-bit AES block -- see BLOCK1
// for the working-register/result semantics and for why the BLOCK0/BLOCK1
// naming doesn't match upper/lower intuitively.
#define KECC_AES_K_AXI_UNIFIED_BLOCK0_REG_OFFSET 0x38
#define KECC_AES_K_AXI_UNIFIED_BLOCK0_W3_MASK 0xffffffff
#define KECC_AES_K_AXI_UNIFIED_BLOCK0_W3_OFFSET 0
#define KECC_AES_K_AXI_UNIFIED_BLOCK0_W3_FIELD \
  ((bitfield_field32_t) { .mask = KECC_AES_K_AXI_UNIFIED_BLOCK0_W3_MASK, .index = KECC_AES_K_AXI_UNIFIED_BLOCK0_W3_OFFSET })
#define KECC_AES_K_AXI_UNIFIED_BLOCK0_W2_MASK 0xffffffff
#define KECC_AES_K_AXI_UNIFIED_BLOCK0_W2_OFFSET 32
#define KECC_AES_K_AXI_UNIFIED_BLOCK0_W2_FIELD \
  ((bitfield_field32_t) { .mask = KECC_AES_K_AXI_UNIFIED_BLOCK0_W2_MASK, .index = KECC_AES_K_AXI_UNIFIED_BLOCK0_W2_OFFSET })

// Word i (0-24) of the 1600-bit Keccak state, word i = bits [64*i +: 64] of
// keccak_din/keccak_dout, matching the vendored core's own w=5*y+x lane
// packing. This is the core's own working storage -- not a staging/mirror
// copy -- overwritten by hardware every one of the 24 permutation rounds
// (not just once at completion). Software must not write KECCAK_DATA[i]
// while a Keccak op is in flight (between NEXT and KECCAK_DONE). (common
// parameters)
#define KECC_AES_K_AXI_UNIFIED_KECCAK_DATA_KECCAK_DATA_FIELD_WIDTH 64
#define KECC_AES_K_AXI_UNIFIED_KECCAK_DATA_KECCAK_DATA_FIELDS_PER_REG 1
#define KECC_AES_K_AXI_UNIFIED_KECCAK_DATA_MULTIREG_COUNT 25

// Word i (0-24) of the 1600-bit Keccak state, word i = bits [64*i +: 64] of
// keccak_din/keccak_dout, matching the vendored core's own w=5*y+x lane
// packing. This is the core's own working storage -- not a staging/mirror
// copy -- overwritten by hardware every one of the 24 permutation rounds
// (not just once at completion). Software must not write KECCAK_DATA[i]
// while a Keccak op is in flight (between NEXT and KECCAK_DONE).
#define KECC_AES_K_AXI_UNIFIED_KECCAK_DATA_0_REG_OFFSET 0x40

// Word i (0-24) of the 1600-bit Keccak state, word i = bits [64*i +: 64] of
// keccak_din/keccak_dout, matching the vendored core's own w=5*y+x lane
// packing. This is the core's own working storage -- not a staging/mirror
// copy -- overwritten by hardware every one of the 24 permutation rounds
// (not just once at completion). Software must not write KECCAK_DATA[i]
// while a Keccak op is in flight (between NEXT and KECCAK_DONE).
#define KECC_AES_K_AXI_UNIFIED_KECCAK_DATA_1_REG_OFFSET 0x48

// Word i (0-24) of the 1600-bit Keccak state, word i = bits [64*i +: 64] of
// keccak_din/keccak_dout, matching the vendored core's own w=5*y+x lane
// packing. This is the core's own working storage -- not a staging/mirror
// copy -- overwritten by hardware every one of the 24 permutation rounds
// (not just once at completion). Software must not write KECCAK_DATA[i]
// while a Keccak op is in flight (between NEXT and KECCAK_DONE).
#define KECC_AES_K_AXI_UNIFIED_KECCAK_DATA_2_REG_OFFSET 0x50

// Word i (0-24) of the 1600-bit Keccak state, word i = bits [64*i +: 64] of
// keccak_din/keccak_dout, matching the vendored core's own w=5*y+x lane
// packing. This is the core's own working storage -- not a staging/mirror
// copy -- overwritten by hardware every one of the 24 permutation rounds
// (not just once at completion). Software must not write KECCAK_DATA[i]
// while a Keccak op is in flight (between NEXT and KECCAK_DONE).
#define KECC_AES_K_AXI_UNIFIED_KECCAK_DATA_3_REG_OFFSET 0x58

// Word i (0-24) of the 1600-bit Keccak state, word i = bits [64*i +: 64] of
// keccak_din/keccak_dout, matching the vendored core's own w=5*y+x lane
// packing. This is the core's own working storage -- not a staging/mirror
// copy -- overwritten by hardware every one of the 24 permutation rounds
// (not just once at completion). Software must not write KECCAK_DATA[i]
// while a Keccak op is in flight (between NEXT and KECCAK_DONE).
#define KECC_AES_K_AXI_UNIFIED_KECCAK_DATA_4_REG_OFFSET 0x60

// Word i (0-24) of the 1600-bit Keccak state, word i = bits [64*i +: 64] of
// keccak_din/keccak_dout, matching the vendored core's own w=5*y+x lane
// packing. This is the core's own working storage -- not a staging/mirror
// copy -- overwritten by hardware every one of the 24 permutation rounds
// (not just once at completion). Software must not write KECCAK_DATA[i]
// while a Keccak op is in flight (between NEXT and KECCAK_DONE).
#define KECC_AES_K_AXI_UNIFIED_KECCAK_DATA_5_REG_OFFSET 0x68

// Word i (0-24) of the 1600-bit Keccak state, word i = bits [64*i +: 64] of
// keccak_din/keccak_dout, matching the vendored core's own w=5*y+x lane
// packing. This is the core's own working storage -- not a staging/mirror
// copy -- overwritten by hardware every one of the 24 permutation rounds
// (not just once at completion). Software must not write KECCAK_DATA[i]
// while a Keccak op is in flight (between NEXT and KECCAK_DONE).
#define KECC_AES_K_AXI_UNIFIED_KECCAK_DATA_6_REG_OFFSET 0x70

// Word i (0-24) of the 1600-bit Keccak state, word i = bits [64*i +: 64] of
// keccak_din/keccak_dout, matching the vendored core's own w=5*y+x lane
// packing. This is the core's own working storage -- not a staging/mirror
// copy -- overwritten by hardware every one of the 24 permutation rounds
// (not just once at completion). Software must not write KECCAK_DATA[i]
// while a Keccak op is in flight (between NEXT and KECCAK_DONE).
#define KECC_AES_K_AXI_UNIFIED_KECCAK_DATA_7_REG_OFFSET 0x78

// Word i (0-24) of the 1600-bit Keccak state, word i = bits [64*i +: 64] of
// keccak_din/keccak_dout, matching the vendored core's own w=5*y+x lane
// packing. This is the core's own working storage -- not a staging/mirror
// copy -- overwritten by hardware every one of the 24 permutation rounds
// (not just once at completion). Software must not write KECCAK_DATA[i]
// while a Keccak op is in flight (between NEXT and KECCAK_DONE).
#define KECC_AES_K_AXI_UNIFIED_KECCAK_DATA_8_REG_OFFSET 0x80

// Word i (0-24) of the 1600-bit Keccak state, word i = bits [64*i +: 64] of
// keccak_din/keccak_dout, matching the vendored core's own w=5*y+x lane
// packing. This is the core's own working storage -- not a staging/mirror
// copy -- overwritten by hardware every one of the 24 permutation rounds
// (not just once at completion). Software must not write KECCAK_DATA[i]
// while a Keccak op is in flight (between NEXT and KECCAK_DONE).
#define KECC_AES_K_AXI_UNIFIED_KECCAK_DATA_9_REG_OFFSET 0x88

// Word i (0-24) of the 1600-bit Keccak state, word i = bits [64*i +: 64] of
// keccak_din/keccak_dout, matching the vendored core's own w=5*y+x lane
// packing. This is the core's own working storage -- not a staging/mirror
// copy -- overwritten by hardware every one of the 24 permutation rounds
// (not just once at completion). Software must not write KECCAK_DATA[i]
// while a Keccak op is in flight (between NEXT and KECCAK_DONE).
#define KECC_AES_K_AXI_UNIFIED_KECCAK_DATA_10_REG_OFFSET 0x90

// Word i (0-24) of the 1600-bit Keccak state, word i = bits [64*i +: 64] of
// keccak_din/keccak_dout, matching the vendored core's own w=5*y+x lane
// packing. This is the core's own working storage -- not a staging/mirror
// copy -- overwritten by hardware every one of the 24 permutation rounds
// (not just once at completion). Software must not write KECCAK_DATA[i]
// while a Keccak op is in flight (between NEXT and KECCAK_DONE).
#define KECC_AES_K_AXI_UNIFIED_KECCAK_DATA_11_REG_OFFSET 0x98

// Word i (0-24) of the 1600-bit Keccak state, word i = bits [64*i +: 64] of
// keccak_din/keccak_dout, matching the vendored core's own w=5*y+x lane
// packing. This is the core's own working storage -- not a staging/mirror
// copy -- overwritten by hardware every one of the 24 permutation rounds
// (not just once at completion). Software must not write KECCAK_DATA[i]
// while a Keccak op is in flight (between NEXT and KECCAK_DONE).
#define KECC_AES_K_AXI_UNIFIED_KECCAK_DATA_12_REG_OFFSET 0xa0

// Word i (0-24) of the 1600-bit Keccak state, word i = bits [64*i +: 64] of
// keccak_din/keccak_dout, matching the vendored core's own w=5*y+x lane
// packing. This is the core's own working storage -- not a staging/mirror
// copy -- overwritten by hardware every one of the 24 permutation rounds
// (not just once at completion). Software must not write KECCAK_DATA[i]
// while a Keccak op is in flight (between NEXT and KECCAK_DONE).
#define KECC_AES_K_AXI_UNIFIED_KECCAK_DATA_13_REG_OFFSET 0xa8

// Word i (0-24) of the 1600-bit Keccak state, word i = bits [64*i +: 64] of
// keccak_din/keccak_dout, matching the vendored core's own w=5*y+x lane
// packing. This is the core's own working storage -- not a staging/mirror
// copy -- overwritten by hardware every one of the 24 permutation rounds
// (not just once at completion). Software must not write KECCAK_DATA[i]
// while a Keccak op is in flight (between NEXT and KECCAK_DONE).
#define KECC_AES_K_AXI_UNIFIED_KECCAK_DATA_14_REG_OFFSET 0xb0

// Word i (0-24) of the 1600-bit Keccak state, word i = bits [64*i +: 64] of
// keccak_din/keccak_dout, matching the vendored core's own w=5*y+x lane
// packing. This is the core's own working storage -- not a staging/mirror
// copy -- overwritten by hardware every one of the 24 permutation rounds
// (not just once at completion). Software must not write KECCAK_DATA[i]
// while a Keccak op is in flight (between NEXT and KECCAK_DONE).
#define KECC_AES_K_AXI_UNIFIED_KECCAK_DATA_15_REG_OFFSET 0xb8

// Word i (0-24) of the 1600-bit Keccak state, word i = bits [64*i +: 64] of
// keccak_din/keccak_dout, matching the vendored core's own w=5*y+x lane
// packing. This is the core's own working storage -- not a staging/mirror
// copy -- overwritten by hardware every one of the 24 permutation rounds
// (not just once at completion). Software must not write KECCAK_DATA[i]
// while a Keccak op is in flight (between NEXT and KECCAK_DONE).
#define KECC_AES_K_AXI_UNIFIED_KECCAK_DATA_16_REG_OFFSET 0xc0

// Word i (0-24) of the 1600-bit Keccak state, word i = bits [64*i +: 64] of
// keccak_din/keccak_dout, matching the vendored core's own w=5*y+x lane
// packing. This is the core's own working storage -- not a staging/mirror
// copy -- overwritten by hardware every one of the 24 permutation rounds
// (not just once at completion). Software must not write KECCAK_DATA[i]
// while a Keccak op is in flight (between NEXT and KECCAK_DONE).
#define KECC_AES_K_AXI_UNIFIED_KECCAK_DATA_17_REG_OFFSET 0xc8

// Word i (0-24) of the 1600-bit Keccak state, word i = bits [64*i +: 64] of
// keccak_din/keccak_dout, matching the vendored core's own w=5*y+x lane
// packing. This is the core's own working storage -- not a staging/mirror
// copy -- overwritten by hardware every one of the 24 permutation rounds
// (not just once at completion). Software must not write KECCAK_DATA[i]
// while a Keccak op is in flight (between NEXT and KECCAK_DONE).
#define KECC_AES_K_AXI_UNIFIED_KECCAK_DATA_18_REG_OFFSET 0xd0

// Word i (0-24) of the 1600-bit Keccak state, word i = bits [64*i +: 64] of
// keccak_din/keccak_dout, matching the vendored core's own w=5*y+x lane
// packing. This is the core's own working storage -- not a staging/mirror
// copy -- overwritten by hardware every one of the 24 permutation rounds
// (not just once at completion). Software must not write KECCAK_DATA[i]
// while a Keccak op is in flight (between NEXT and KECCAK_DONE).
#define KECC_AES_K_AXI_UNIFIED_KECCAK_DATA_19_REG_OFFSET 0xd8

// Word i (0-24) of the 1600-bit Keccak state, word i = bits [64*i +: 64] of
// keccak_din/keccak_dout, matching the vendored core's own w=5*y+x lane
// packing. This is the core's own working storage -- not a staging/mirror
// copy -- overwritten by hardware every one of the 24 permutation rounds
// (not just once at completion). Software must not write KECCAK_DATA[i]
// while a Keccak op is in flight (between NEXT and KECCAK_DONE).
#define KECC_AES_K_AXI_UNIFIED_KECCAK_DATA_20_REG_OFFSET 0xe0

// Word i (0-24) of the 1600-bit Keccak state, word i = bits [64*i +: 64] of
// keccak_din/keccak_dout, matching the vendored core's own w=5*y+x lane
// packing. This is the core's own working storage -- not a staging/mirror
// copy -- overwritten by hardware every one of the 24 permutation rounds
// (not just once at completion). Software must not write KECCAK_DATA[i]
// while a Keccak op is in flight (between NEXT and KECCAK_DONE).
#define KECC_AES_K_AXI_UNIFIED_KECCAK_DATA_21_REG_OFFSET 0xe8

// Word i (0-24) of the 1600-bit Keccak state, word i = bits [64*i +: 64] of
// keccak_din/keccak_dout, matching the vendored core's own w=5*y+x lane
// packing. This is the core's own working storage -- not a staging/mirror
// copy -- overwritten by hardware every one of the 24 permutation rounds
// (not just once at completion). Software must not write KECCAK_DATA[i]
// while a Keccak op is in flight (between NEXT and KECCAK_DONE).
#define KECC_AES_K_AXI_UNIFIED_KECCAK_DATA_22_REG_OFFSET 0xf0

// Word i (0-24) of the 1600-bit Keccak state, word i = bits [64*i +: 64] of
// keccak_din/keccak_dout, matching the vendored core's own w=5*y+x lane
// packing. This is the core's own working storage -- not a staging/mirror
// copy -- overwritten by hardware every one of the 24 permutation rounds
// (not just once at completion). Software must not write KECCAK_DATA[i]
// while a Keccak op is in flight (between NEXT and KECCAK_DONE).
#define KECC_AES_K_AXI_UNIFIED_KECCAK_DATA_23_REG_OFFSET 0xf8

// Word i (0-24) of the 1600-bit Keccak state, word i = bits [64*i +: 64] of
// keccak_din/keccak_dout, matching the vendored core's own w=5*y+x lane
// packing. This is the core's own working storage -- not a staging/mirror
// copy -- overwritten by hardware every one of the 24 permutation rounds
// (not just once at completion). Software must not write KECCAK_DATA[i]
// while a Keccak op is in flight (between NEXT and KECCAK_DONE).
#define KECC_AES_K_AXI_UNIFIED_KECCAK_DATA_24_REG_OFFSET 0x100

#ifdef __cplusplus
}  // extern "C"
#endif
#endif  // _KECC_AES_K_AXI_UNIFIED_REG_DEFS_
// End generated register defines for kecc_aes_k_axi_unified