// Generated register defines for gf2

#ifndef _GF2_REG_DEFS_
#define _GF2_REG_DEFS_

#ifdef __cplusplus
extern "C" {
#endif
// Register width
#define GF2_PARAM_REG_WIDTH 64

// 128-bit multiplicand for the ACC_WIDTH=128 op (bf128_mul()), one 64-bit
// limb per word, word 0 = low limb (common parameters)
#define GF2_LHS128_LHS128_FIELD_WIDTH 64
#define GF2_LHS128_LHS128_FIELDS_PER_REG 1
#define GF2_LHS128_MULTIREG_COUNT 2

// 128-bit multiplicand for the ACC_WIDTH=128 op (bf128_mul()), one 64-bit
// limb per word, word 0 = low limb
#define GF2_LHS128_0_REG_OFFSET 0x0

// 128-bit multiplicand for the ACC_WIDTH=128 op (bf128_mul()), one 64-bit
// limb per word, word 0 = low limb
#define GF2_LHS128_1_REG_OFFSET 0x8

// 384-bit multiplicand for the ACC_WIDTH=384 op (bf384_mul_128_inplace()),
// one 64-bit limb per word, word 0 = low limb (common parameters)
#define GF2_LHS384_LHS384_FIELD_WIDTH 64
#define GF2_LHS384_LHS384_FIELDS_PER_REG 1
#define GF2_LHS384_MULTIREG_COUNT 6

// 384-bit multiplicand for the ACC_WIDTH=384 op (bf384_mul_128_inplace()),
// one 64-bit limb per word, word 0 = low limb
#define GF2_LHS384_0_REG_OFFSET 0x10

// 384-bit multiplicand for the ACC_WIDTH=384 op (bf384_mul_128_inplace()),
// one 64-bit limb per word, word 0 = low limb
#define GF2_LHS384_1_REG_OFFSET 0x18

// 384-bit multiplicand for the ACC_WIDTH=384 op (bf384_mul_128_inplace()),
// one 64-bit limb per word, word 0 = low limb
#define GF2_LHS384_2_REG_OFFSET 0x20

// 384-bit multiplicand for the ACC_WIDTH=384 op (bf384_mul_128_inplace()),
// one 64-bit limb per word, word 0 = low limb
#define GF2_LHS384_3_REG_OFFSET 0x28

// 384-bit multiplicand for the ACC_WIDTH=384 op (bf384_mul_128_inplace()),
// one 64-bit limb per word, word 0 = low limb
#define GF2_LHS384_4_REG_OFFSET 0x30

// 384-bit multiplicand for the ACC_WIDTH=384 op (bf384_mul_128_inplace()),
// one 64-bit limb per word, word 0 = low limb
#define GF2_LHS384_5_REG_OFFSET 0x38

// 128-bit multiplier, shared by both ops, one 64-bit limb per word, word 0 =
// low limb (common parameters)
#define GF2_RHS_RHS_FIELD_WIDTH 64
#define GF2_RHS_RHS_FIELDS_PER_REG 1
#define GF2_RHS_MULTIREG_COUNT 2

// 128-bit multiplier, shared by both ops, one 64-bit limb per word, word 0 =
// low limb
#define GF2_RHS_0_REG_OFFSET 0x40

// 128-bit multiplier, shared by both ops, one 64-bit limb per word, word 0 =
// low limb
#define GF2_RHS_1_REG_OFFSET 0x48

// 128-bit result (read-only), valid after a mode=0 op, one 64-bit limb per
// word (common parameters)
#define GF2_RES128_RES128_FIELD_WIDTH 64
#define GF2_RES128_RES128_FIELDS_PER_REG 1
#define GF2_RES128_MULTIREG_COUNT 2

// 128-bit result (read-only), valid after a mode=0 op, one 64-bit limb per
// word
#define GF2_RES128_0_REG_OFFSET 0x50

// 128-bit result (read-only), valid after a mode=0 op, one 64-bit limb per
// word
#define GF2_RES128_1_REG_OFFSET 0x58

// 384-bit result (read-only), valid after a mode=1 op, one 64-bit limb per
// word (common parameters)
#define GF2_RES384_RES384_FIELD_WIDTH 64
#define GF2_RES384_RES384_FIELDS_PER_REG 1
#define GF2_RES384_MULTIREG_COUNT 6

// 384-bit result (read-only), valid after a mode=1 op, one 64-bit limb per
// word
#define GF2_RES384_0_REG_OFFSET 0x60

// 384-bit result (read-only), valid after a mode=1 op, one 64-bit limb per
// word
#define GF2_RES384_1_REG_OFFSET 0x68

// 384-bit result (read-only), valid after a mode=1 op, one 64-bit limb per
// word
#define GF2_RES384_2_REG_OFFSET 0x70

// 384-bit result (read-only), valid after a mode=1 op, one 64-bit limb per
// word
#define GF2_RES384_3_REG_OFFSET 0x78

// 384-bit result (read-only), valid after a mode=1 op, one 64-bit limb per
// word
#define GF2_RES384_4_REG_OFFSET 0x80

// 384-bit result (read-only), valid after a mode=1 op, one 64-bit limb per
// word
#define GF2_RES384_5_REG_OFFSET 0x88

// Control register -- sw sets NEXT to pulse a multiply, then clears it (same
// explicit set/poll/clear convention as keccak_ip's CSREG.START)
#define GF2_CTRL_REG_OFFSET 0x90
#define GF2_CTRL_NEXT_BIT 0
#define GF2_CTRL_MODE384_BIT 1

// Status register, hardware-driven, read-only from software
#define GF2_STATUS_REG_OFFSET 0x98
#define GF2_STATUS_READY_BIT 0
#define GF2_STATUS_VALID_BIT 1

#ifdef __cplusplus
}  // extern "C"
#endif
#endif  // _GF2_REG_DEFS_
// End generated register defines for gf2