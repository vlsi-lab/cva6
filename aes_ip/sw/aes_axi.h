// Generated register defines for aes

#ifndef _AES_REG_DEFS_
#define _AES_REG_DEFS_

#ifdef __cplusplus
extern "C" {
#endif
// Register width
#define AES_PARAM_REG_WIDTH 64

// 128-bit AES-128 key, word 0 = low 64 bits, word 1 = high 64 bits (common
// parameters)
#define AES_KEY_KEY_FIELD_WIDTH 64
#define AES_KEY_KEY_FIELDS_PER_REG 1
#define AES_KEY_MULTIREG_COUNT 2

// 128-bit AES-128 key, word 0 = low 64 bits, word 1 = high 64 bits
#define AES_KEY_0_REG_OFFSET 0x0

// 128-bit AES-128 key, word 0 = low 64 bits, word 1 = high 64 bits
#define AES_KEY_1_REG_OFFSET 0x8

// 128-bit input block, word 0 = low 64 bits, word 1 = high 64 bits (common
// parameters)
#define AES_BLOCK_BLOCK_FIELD_WIDTH 64
#define AES_BLOCK_BLOCK_FIELDS_PER_REG 1
#define AES_BLOCK_MULTIREG_COUNT 2

// 128-bit input block, word 0 = low 64 bits, word 1 = high 64 bits
#define AES_BLOCK_0_REG_OFFSET 0x10

// 128-bit input block, word 0 = low 64 bits, word 1 = high 64 bits
#define AES_BLOCK_1_REG_OFFSET 0x18

// 128-bit result (read-only), word 0 = low 64 bits, word 1 = high 64 bits
// (common parameters)
#define AES_RESULT_RESULT_FIELD_WIDTH 64
#define AES_RESULT_RESULT_FIELDS_PER_REG 1
#define AES_RESULT_MULTIREG_COUNT 2

// 128-bit result (read-only), word 0 = low 64 bits, word 1 = high 64 bits
#define AES_RESULT_0_REG_OFFSET 0x20

// 128-bit result (read-only), word 0 = low 64 bits, word 1 = high 64 bits
#define AES_RESULT_1_REG_OFFSET 0x28

// Control register -- sw sets a bit to pulse the corresponding operation,
// then clears it (same explicit set/poll/clear convention as keccak_ip's
// CSREG.START)
#define AES_CTRL_REG_OFFSET 0x30
#define AES_CTRL_INIT_BIT 0
#define AES_CTRL_NEXT_BIT 1
#define AES_CTRL_CTR_INC_BIT 2

// Status register, hardware-driven, read-only from software
#define AES_STATUS_REG_OFFSET 0x38
#define AES_STATUS_READY_BIT 0
#define AES_STATUS_VALID_BIT 1

#ifdef __cplusplus
}  // extern "C"
#endif
#endif  // _AES_REG_DEFS_
// End generated register defines for aes