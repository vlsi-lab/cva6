// Generated register defines for kecc_aes_k_axi

#ifndef _KECC_AES_K_AXI_REG_DEFS_
#define _KECC_AES_K_AXI_REG_DEFS_

#ifdef __cplusplus
extern "C" {
#endif
// Register width
#define KECC_AES_K_AXI_PARAM_REG_WIDTH 64

// Control register for the kecc_aes_k_axi (v2) accelerator wrapper
#define KECC_AES_K_AXI_CTRL_REG_OFFSET 0x0
#define KECC_AES_K_AXI_CTRL_ZEROIZE_BIT 0
#define KECC_AES_K_AXI_CTRL_SEL_BIT 1
#define KECC_AES_K_AXI_CTRL_ENCDEC_BIT 2
#define KECC_AES_K_AXI_CTRL_KEYLEN_BIT 3
#define KECC_AES_K_AXI_CTRL_INIT_BIT 4
#define KECC_AES_K_AXI_CTRL_NEXT_BIT 5

// Status register for the kecc_aes_k_axi (v2) accelerator wrapper
#define KECC_AES_K_AXI_STATUS_REG_OFFSET 0x8
#define KECC_AES_K_AXI_STATUS_READY_BIT 0
#define KECC_AES_K_AXI_STATUS_RESULT_VALID_BIT 1
#define KECC_AES_K_AXI_STATUS_KECCAK_DONE_BIT 2

// Word i (0-3) of the 256-bit AES key input, word i = key[64*i +: 64]. AES
// only. Software-owned staging register, read directly by the core -- do not
// write while an operation is in flight. (common parameters)
#define KECC_AES_K_AXI_KEY_KEY_FIELD_WIDTH 64
#define KECC_AES_K_AXI_KEY_KEY_FIELDS_PER_REG 1
#define KECC_AES_K_AXI_KEY_MULTIREG_COUNT 4

// Word i (0-3) of the 256-bit AES key input, word i = key[64*i +: 64]. AES
// only. Software-owned staging register, read directly by the core -- do not
// write while an operation is in flight.
#define KECC_AES_K_AXI_KEY_0_REG_OFFSET 0x10

// Word i (0-3) of the 256-bit AES key input, word i = key[64*i +: 64]. AES
// only. Software-owned staging register, read directly by the core -- do not
// write while an operation is in flight.
#define KECC_AES_K_AXI_KEY_1_REG_OFFSET 0x18

// Word i (0-3) of the 256-bit AES key input, word i = key[64*i +: 64]. AES
// only. Software-owned staging register, read directly by the core -- do not
// write while an operation is in flight.
#define KECC_AES_K_AXI_KEY_2_REG_OFFSET 0x20

// Word i (0-3) of the 256-bit AES key input, word i = key[64*i +: 64]. AES
// only. Software-owned staging register, read directly by the core -- do not
// write while an operation is in flight.
#define KECC_AES_K_AXI_KEY_3_REG_OFFSET 0x28

// Word i (0-1) of the 128-bit AES block input, word i = block[64*i +: 64].
// AES only. Software-owned staging register, read directly by the core -- do
// not write while an operation is in flight. (common parameters)
#define KECC_AES_K_AXI_BLOCK_BLOCK_FIELD_WIDTH 64
#define KECC_AES_K_AXI_BLOCK_BLOCK_FIELDS_PER_REG 1
#define KECC_AES_K_AXI_BLOCK_MULTIREG_COUNT 2

// Word i (0-1) of the 128-bit AES block input, word i = block[64*i +: 64].
// AES only. Software-owned staging register, read directly by the core -- do
// not write while an operation is in flight.
#define KECC_AES_K_AXI_BLOCK_0_REG_OFFSET 0x30

// Word i (0-1) of the 128-bit AES block input, word i = block[64*i +: 64].
// AES only. Software-owned staging register, read directly by the core -- do
// not write while an operation is in flight.
#define KECC_AES_K_AXI_BLOCK_1_REG_OFFSET 0x38

// Word i (0-1) of the 128-bit AES result output, word i = result[64*i +:
// 64]. AES only. Hardware-driven, mirrors the core's result output for as
// long as STATUS.RESULT_VALID is asserted. (common parameters)
#define KECC_AES_K_AXI_RESULT_RESULT_FIELD_WIDTH 64
#define KECC_AES_K_AXI_RESULT_RESULT_FIELDS_PER_REG 1
#define KECC_AES_K_AXI_RESULT_MULTIREG_COUNT 2

// Word i (0-1) of the 128-bit AES result output, word i = result[64*i +:
// 64]. AES only. Hardware-driven, mirrors the core's result output for as
// long as STATUS.RESULT_VALID is asserted.
#define KECC_AES_K_AXI_RESULT_0_REG_OFFSET 0x40

// Word i (0-1) of the 128-bit AES result output, word i = result[64*i +:
// 64]. AES only. Hardware-driven, mirrors the core's result output for as
// long as STATUS.RESULT_VALID is asserted.
#define KECC_AES_K_AXI_RESULT_1_REG_OFFSET 0x48

// Word i (0-24) of the 1600-bit Keccak state, word i = bits [64*i +: 64] of
// keccak_din/keccak_dout. This is the core's own working storage (state_reg)
// -- not a staging/mirror copy -- so it must not be written while a Keccak
// op is in flight (between NEXT and KECCAK_DONE). Software writes it before
// pulsing NEXT (feeds keccak_din); hardware overwrites it with the final
// permuted state on the keccak_done pulse (captures keccak_dout). (common
// parameters)
#define KECC_AES_K_AXI_KECCAK_DATA_KECCAK_DATA_FIELD_WIDTH 64
#define KECC_AES_K_AXI_KECCAK_DATA_KECCAK_DATA_FIELDS_PER_REG 1
#define KECC_AES_K_AXI_KECCAK_DATA_MULTIREG_COUNT 25

// Word i (0-24) of the 1600-bit Keccak state, word i = bits [64*i +: 64] of
// keccak_din/keccak_dout. This is the core's own working storage (state_reg)
// -- not a staging/mirror copy -- so it must not be written while a Keccak
// op is in flight (between NEXT and KECCAK_DONE). Software writes it before
// pulsing NEXT (feeds keccak_din); hardware overwrites it with the final
// permuted state on the keccak_done pulse (captures keccak_dout).
#define KECC_AES_K_AXI_KECCAK_DATA_0_REG_OFFSET 0x50

// Word i (0-24) of the 1600-bit Keccak state, word i = bits [64*i +: 64] of
// keccak_din/keccak_dout. This is the core's own working storage (state_reg)
// -- not a staging/mirror copy -- so it must not be written while a Keccak
// op is in flight (between NEXT and KECCAK_DONE). Software writes it before
// pulsing NEXT (feeds keccak_din); hardware overwrites it with the final
// permuted state on the keccak_done pulse (captures keccak_dout).
#define KECC_AES_K_AXI_KECCAK_DATA_1_REG_OFFSET 0x58

// Word i (0-24) of the 1600-bit Keccak state, word i = bits [64*i +: 64] of
// keccak_din/keccak_dout. This is the core's own working storage (state_reg)
// -- not a staging/mirror copy -- so it must not be written while a Keccak
// op is in flight (between NEXT and KECCAK_DONE). Software writes it before
// pulsing NEXT (feeds keccak_din); hardware overwrites it with the final
// permuted state on the keccak_done pulse (captures keccak_dout).
#define KECC_AES_K_AXI_KECCAK_DATA_2_REG_OFFSET 0x60

// Word i (0-24) of the 1600-bit Keccak state, word i = bits [64*i +: 64] of
// keccak_din/keccak_dout. This is the core's own working storage (state_reg)
// -- not a staging/mirror copy -- so it must not be written while a Keccak
// op is in flight (between NEXT and KECCAK_DONE). Software writes it before
// pulsing NEXT (feeds keccak_din); hardware overwrites it with the final
// permuted state on the keccak_done pulse (captures keccak_dout).
#define KECC_AES_K_AXI_KECCAK_DATA_3_REG_OFFSET 0x68

// Word i (0-24) of the 1600-bit Keccak state, word i = bits [64*i +: 64] of
// keccak_din/keccak_dout. This is the core's own working storage (state_reg)
// -- not a staging/mirror copy -- so it must not be written while a Keccak
// op is in flight (between NEXT and KECCAK_DONE). Software writes it before
// pulsing NEXT (feeds keccak_din); hardware overwrites it with the final
// permuted state on the keccak_done pulse (captures keccak_dout).
#define KECC_AES_K_AXI_KECCAK_DATA_4_REG_OFFSET 0x70

// Word i (0-24) of the 1600-bit Keccak state, word i = bits [64*i +: 64] of
// keccak_din/keccak_dout. This is the core's own working storage (state_reg)
// -- not a staging/mirror copy -- so it must not be written while a Keccak
// op is in flight (between NEXT and KECCAK_DONE). Software writes it before
// pulsing NEXT (feeds keccak_din); hardware overwrites it with the final
// permuted state on the keccak_done pulse (captures keccak_dout).
#define KECC_AES_K_AXI_KECCAK_DATA_5_REG_OFFSET 0x78

// Word i (0-24) of the 1600-bit Keccak state, word i = bits [64*i +: 64] of
// keccak_din/keccak_dout. This is the core's own working storage (state_reg)
// -- not a staging/mirror copy -- so it must not be written while a Keccak
// op is in flight (between NEXT and KECCAK_DONE). Software writes it before
// pulsing NEXT (feeds keccak_din); hardware overwrites it with the final
// permuted state on the keccak_done pulse (captures keccak_dout).
#define KECC_AES_K_AXI_KECCAK_DATA_6_REG_OFFSET 0x80

// Word i (0-24) of the 1600-bit Keccak state, word i = bits [64*i +: 64] of
// keccak_din/keccak_dout. This is the core's own working storage (state_reg)
// -- not a staging/mirror copy -- so it must not be written while a Keccak
// op is in flight (between NEXT and KECCAK_DONE). Software writes it before
// pulsing NEXT (feeds keccak_din); hardware overwrites it with the final
// permuted state on the keccak_done pulse (captures keccak_dout).
#define KECC_AES_K_AXI_KECCAK_DATA_7_REG_OFFSET 0x88

// Word i (0-24) of the 1600-bit Keccak state, word i = bits [64*i +: 64] of
// keccak_din/keccak_dout. This is the core's own working storage (state_reg)
// -- not a staging/mirror copy -- so it must not be written while a Keccak
// op is in flight (between NEXT and KECCAK_DONE). Software writes it before
// pulsing NEXT (feeds keccak_din); hardware overwrites it with the final
// permuted state on the keccak_done pulse (captures keccak_dout).
#define KECC_AES_K_AXI_KECCAK_DATA_8_REG_OFFSET 0x90

// Word i (0-24) of the 1600-bit Keccak state, word i = bits [64*i +: 64] of
// keccak_din/keccak_dout. This is the core's own working storage (state_reg)
// -- not a staging/mirror copy -- so it must not be written while a Keccak
// op is in flight (between NEXT and KECCAK_DONE). Software writes it before
// pulsing NEXT (feeds keccak_din); hardware overwrites it with the final
// permuted state on the keccak_done pulse (captures keccak_dout).
#define KECC_AES_K_AXI_KECCAK_DATA_9_REG_OFFSET 0x98

// Word i (0-24) of the 1600-bit Keccak state, word i = bits [64*i +: 64] of
// keccak_din/keccak_dout. This is the core's own working storage (state_reg)
// -- not a staging/mirror copy -- so it must not be written while a Keccak
// op is in flight (between NEXT and KECCAK_DONE). Software writes it before
// pulsing NEXT (feeds keccak_din); hardware overwrites it with the final
// permuted state on the keccak_done pulse (captures keccak_dout).
#define KECC_AES_K_AXI_KECCAK_DATA_10_REG_OFFSET 0xa0

// Word i (0-24) of the 1600-bit Keccak state, word i = bits [64*i +: 64] of
// keccak_din/keccak_dout. This is the core's own working storage (state_reg)
// -- not a staging/mirror copy -- so it must not be written while a Keccak
// op is in flight (between NEXT and KECCAK_DONE). Software writes it before
// pulsing NEXT (feeds keccak_din); hardware overwrites it with the final
// permuted state on the keccak_done pulse (captures keccak_dout).
#define KECC_AES_K_AXI_KECCAK_DATA_11_REG_OFFSET 0xa8

// Word i (0-24) of the 1600-bit Keccak state, word i = bits [64*i +: 64] of
// keccak_din/keccak_dout. This is the core's own working storage (state_reg)
// -- not a staging/mirror copy -- so it must not be written while a Keccak
// op is in flight (between NEXT and KECCAK_DONE). Software writes it before
// pulsing NEXT (feeds keccak_din); hardware overwrites it with the final
// permuted state on the keccak_done pulse (captures keccak_dout).
#define KECC_AES_K_AXI_KECCAK_DATA_12_REG_OFFSET 0xb0

// Word i (0-24) of the 1600-bit Keccak state, word i = bits [64*i +: 64] of
// keccak_din/keccak_dout. This is the core's own working storage (state_reg)
// -- not a staging/mirror copy -- so it must not be written while a Keccak
// op is in flight (between NEXT and KECCAK_DONE). Software writes it before
// pulsing NEXT (feeds keccak_din); hardware overwrites it with the final
// permuted state on the keccak_done pulse (captures keccak_dout).
#define KECC_AES_K_AXI_KECCAK_DATA_13_REG_OFFSET 0xb8

// Word i (0-24) of the 1600-bit Keccak state, word i = bits [64*i +: 64] of
// keccak_din/keccak_dout. This is the core's own working storage (state_reg)
// -- not a staging/mirror copy -- so it must not be written while a Keccak
// op is in flight (between NEXT and KECCAK_DONE). Software writes it before
// pulsing NEXT (feeds keccak_din); hardware overwrites it with the final
// permuted state on the keccak_done pulse (captures keccak_dout).
#define KECC_AES_K_AXI_KECCAK_DATA_14_REG_OFFSET 0xc0

// Word i (0-24) of the 1600-bit Keccak state, word i = bits [64*i +: 64] of
// keccak_din/keccak_dout. This is the core's own working storage (state_reg)
// -- not a staging/mirror copy -- so it must not be written while a Keccak
// op is in flight (between NEXT and KECCAK_DONE). Software writes it before
// pulsing NEXT (feeds keccak_din); hardware overwrites it with the final
// permuted state on the keccak_done pulse (captures keccak_dout).
#define KECC_AES_K_AXI_KECCAK_DATA_15_REG_OFFSET 0xc8

// Word i (0-24) of the 1600-bit Keccak state, word i = bits [64*i +: 64] of
// keccak_din/keccak_dout. This is the core's own working storage (state_reg)
// -- not a staging/mirror copy -- so it must not be written while a Keccak
// op is in flight (between NEXT and KECCAK_DONE). Software writes it before
// pulsing NEXT (feeds keccak_din); hardware overwrites it with the final
// permuted state on the keccak_done pulse (captures keccak_dout).
#define KECC_AES_K_AXI_KECCAK_DATA_16_REG_OFFSET 0xd0

// Word i (0-24) of the 1600-bit Keccak state, word i = bits [64*i +: 64] of
// keccak_din/keccak_dout. This is the core's own working storage (state_reg)
// -- not a staging/mirror copy -- so it must not be written while a Keccak
// op is in flight (between NEXT and KECCAK_DONE). Software writes it before
// pulsing NEXT (feeds keccak_din); hardware overwrites it with the final
// permuted state on the keccak_done pulse (captures keccak_dout).
#define KECC_AES_K_AXI_KECCAK_DATA_17_REG_OFFSET 0xd8

// Word i (0-24) of the 1600-bit Keccak state, word i = bits [64*i +: 64] of
// keccak_din/keccak_dout. This is the core's own working storage (state_reg)
// -- not a staging/mirror copy -- so it must not be written while a Keccak
// op is in flight (between NEXT and KECCAK_DONE). Software writes it before
// pulsing NEXT (feeds keccak_din); hardware overwrites it with the final
// permuted state on the keccak_done pulse (captures keccak_dout).
#define KECC_AES_K_AXI_KECCAK_DATA_18_REG_OFFSET 0xe0

// Word i (0-24) of the 1600-bit Keccak state, word i = bits [64*i +: 64] of
// keccak_din/keccak_dout. This is the core's own working storage (state_reg)
// -- not a staging/mirror copy -- so it must not be written while a Keccak
// op is in flight (between NEXT and KECCAK_DONE). Software writes it before
// pulsing NEXT (feeds keccak_din); hardware overwrites it with the final
// permuted state on the keccak_done pulse (captures keccak_dout).
#define KECC_AES_K_AXI_KECCAK_DATA_19_REG_OFFSET 0xe8

// Word i (0-24) of the 1600-bit Keccak state, word i = bits [64*i +: 64] of
// keccak_din/keccak_dout. This is the core's own working storage (state_reg)
// -- not a staging/mirror copy -- so it must not be written while a Keccak
// op is in flight (between NEXT and KECCAK_DONE). Software writes it before
// pulsing NEXT (feeds keccak_din); hardware overwrites it with the final
// permuted state on the keccak_done pulse (captures keccak_dout).
#define KECC_AES_K_AXI_KECCAK_DATA_20_REG_OFFSET 0xf0

// Word i (0-24) of the 1600-bit Keccak state, word i = bits [64*i +: 64] of
// keccak_din/keccak_dout. This is the core's own working storage (state_reg)
// -- not a staging/mirror copy -- so it must not be written while a Keccak
// op is in flight (between NEXT and KECCAK_DONE). Software writes it before
// pulsing NEXT (feeds keccak_din); hardware overwrites it with the final
// permuted state on the keccak_done pulse (captures keccak_dout).
#define KECC_AES_K_AXI_KECCAK_DATA_21_REG_OFFSET 0xf8

// Word i (0-24) of the 1600-bit Keccak state, word i = bits [64*i +: 64] of
// keccak_din/keccak_dout. This is the core's own working storage (state_reg)
// -- not a staging/mirror copy -- so it must not be written while a Keccak
// op is in flight (between NEXT and KECCAK_DONE). Software writes it before
// pulsing NEXT (feeds keccak_din); hardware overwrites it with the final
// permuted state on the keccak_done pulse (captures keccak_dout).
#define KECC_AES_K_AXI_KECCAK_DATA_22_REG_OFFSET 0x100

// Word i (0-24) of the 1600-bit Keccak state, word i = bits [64*i +: 64] of
// keccak_din/keccak_dout. This is the core's own working storage (state_reg)
// -- not a staging/mirror copy -- so it must not be written while a Keccak
// op is in flight (between NEXT and KECCAK_DONE). Software writes it before
// pulsing NEXT (feeds keccak_din); hardware overwrites it with the final
// permuted state on the keccak_done pulse (captures keccak_dout).
#define KECC_AES_K_AXI_KECCAK_DATA_23_REG_OFFSET 0x108

// Word i (0-24) of the 1600-bit Keccak state, word i = bits [64*i +: 64] of
// keccak_din/keccak_dout. This is the core's own working storage (state_reg)
// -- not a staging/mirror copy -- so it must not be written while a Keccak
// op is in flight (between NEXT and KECCAK_DONE). Software writes it before
// pulsing NEXT (feeds keccak_din); hardware overwrites it with the final
// permuted state on the keccak_done pulse (captures keccak_dout).
#define KECC_AES_K_AXI_KECCAK_DATA_24_REG_OFFSET 0x110

#ifdef __cplusplus
}  // extern "C"
#endif
#endif  // _KECC_AES_K_AXI_REG_DEFS_
// End generated register defines for kecc_aes_k_axi