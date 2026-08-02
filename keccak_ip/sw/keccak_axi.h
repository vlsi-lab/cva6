// Generated register defines for keccak

#ifndef _KECCAK_REG_DEFS_
#define _KECCAK_REG_DEFS_

#ifdef __cplusplus
extern "C" {
#endif
// Register width
#define KECCAK_PARAM_REG_WIDTH 64

// Control register for the Keccak AXI Accellerator
#define KECCAK_CTRL_REG_OFFSET 0x0
#define KECCAK_CTRL_START_BIT 0
#define KECCAK_CTRL_DONE_BIT 1

// Word i (0-24) of the 1600-bit Keccak state. This is the permutation
// engine's own working storage -- not a staging/mirror copy -- so it must
// not be written while a permutation is in flight (between START and DONE).
// (common parameters)
#define KECCAK_DATA_DATA_FIELD_WIDTH 64
#define KECCAK_DATA_DATA_FIELDS_PER_REG 1
#define KECCAK_DATA_MULTIREG_COUNT 25

// Word i (0-24) of the 1600-bit Keccak state. This is the permutation
// engine's own working storage -- not a staging/mirror copy -- so it must
// not be written while a permutation is in flight (between START and DONE).
#define KECCAK_DATA_0_REG_OFFSET 0x8

// Word i (0-24) of the 1600-bit Keccak state. This is the permutation
// engine's own working storage -- not a staging/mirror copy -- so it must
// not be written while a permutation is in flight (between START and DONE).
#define KECCAK_DATA_1_REG_OFFSET 0x10

// Word i (0-24) of the 1600-bit Keccak state. This is the permutation
// engine's own working storage -- not a staging/mirror copy -- so it must
// not be written while a permutation is in flight (between START and DONE).
#define KECCAK_DATA_2_REG_OFFSET 0x18

// Word i (0-24) of the 1600-bit Keccak state. This is the permutation
// engine's own working storage -- not a staging/mirror copy -- so it must
// not be written while a permutation is in flight (between START and DONE).
#define KECCAK_DATA_3_REG_OFFSET 0x20

// Word i (0-24) of the 1600-bit Keccak state. This is the permutation
// engine's own working storage -- not a staging/mirror copy -- so it must
// not be written while a permutation is in flight (between START and DONE).
#define KECCAK_DATA_4_REG_OFFSET 0x28

// Word i (0-24) of the 1600-bit Keccak state. This is the permutation
// engine's own working storage -- not a staging/mirror copy -- so it must
// not be written while a permutation is in flight (between START and DONE).
#define KECCAK_DATA_5_REG_OFFSET 0x30

// Word i (0-24) of the 1600-bit Keccak state. This is the permutation
// engine's own working storage -- not a staging/mirror copy -- so it must
// not be written while a permutation is in flight (between START and DONE).
#define KECCAK_DATA_6_REG_OFFSET 0x38

// Word i (0-24) of the 1600-bit Keccak state. This is the permutation
// engine's own working storage -- not a staging/mirror copy -- so it must
// not be written while a permutation is in flight (between START and DONE).
#define KECCAK_DATA_7_REG_OFFSET 0x40

// Word i (0-24) of the 1600-bit Keccak state. This is the permutation
// engine's own working storage -- not a staging/mirror copy -- so it must
// not be written while a permutation is in flight (between START and DONE).
#define KECCAK_DATA_8_REG_OFFSET 0x48

// Word i (0-24) of the 1600-bit Keccak state. This is the permutation
// engine's own working storage -- not a staging/mirror copy -- so it must
// not be written while a permutation is in flight (between START and DONE).
#define KECCAK_DATA_9_REG_OFFSET 0x50

// Word i (0-24) of the 1600-bit Keccak state. This is the permutation
// engine's own working storage -- not a staging/mirror copy -- so it must
// not be written while a permutation is in flight (between START and DONE).
#define KECCAK_DATA_10_REG_OFFSET 0x58

// Word i (0-24) of the 1600-bit Keccak state. This is the permutation
// engine's own working storage -- not a staging/mirror copy -- so it must
// not be written while a permutation is in flight (between START and DONE).
#define KECCAK_DATA_11_REG_OFFSET 0x60

// Word i (0-24) of the 1600-bit Keccak state. This is the permutation
// engine's own working storage -- not a staging/mirror copy -- so it must
// not be written while a permutation is in flight (between START and DONE).
#define KECCAK_DATA_12_REG_OFFSET 0x68

// Word i (0-24) of the 1600-bit Keccak state. This is the permutation
// engine's own working storage -- not a staging/mirror copy -- so it must
// not be written while a permutation is in flight (between START and DONE).
#define KECCAK_DATA_13_REG_OFFSET 0x70

// Word i (0-24) of the 1600-bit Keccak state. This is the permutation
// engine's own working storage -- not a staging/mirror copy -- so it must
// not be written while a permutation is in flight (between START and DONE).
#define KECCAK_DATA_14_REG_OFFSET 0x78

// Word i (0-24) of the 1600-bit Keccak state. This is the permutation
// engine's own working storage -- not a staging/mirror copy -- so it must
// not be written while a permutation is in flight (between START and DONE).
#define KECCAK_DATA_15_REG_OFFSET 0x80

// Word i (0-24) of the 1600-bit Keccak state. This is the permutation
// engine's own working storage -- not a staging/mirror copy -- so it must
// not be written while a permutation is in flight (between START and DONE).
#define KECCAK_DATA_16_REG_OFFSET 0x88

// Word i (0-24) of the 1600-bit Keccak state. This is the permutation
// engine's own working storage -- not a staging/mirror copy -- so it must
// not be written while a permutation is in flight (between START and DONE).
#define KECCAK_DATA_17_REG_OFFSET 0x90

// Word i (0-24) of the 1600-bit Keccak state. This is the permutation
// engine's own working storage -- not a staging/mirror copy -- so it must
// not be written while a permutation is in flight (between START and DONE).
#define KECCAK_DATA_18_REG_OFFSET 0x98

// Word i (0-24) of the 1600-bit Keccak state. This is the permutation
// engine's own working storage -- not a staging/mirror copy -- so it must
// not be written while a permutation is in flight (between START and DONE).
#define KECCAK_DATA_19_REG_OFFSET 0xa0

// Word i (0-24) of the 1600-bit Keccak state. This is the permutation
// engine's own working storage -- not a staging/mirror copy -- so it must
// not be written while a permutation is in flight (between START and DONE).
#define KECCAK_DATA_20_REG_OFFSET 0xa8

// Word i (0-24) of the 1600-bit Keccak state. This is the permutation
// engine's own working storage -- not a staging/mirror copy -- so it must
// not be written while a permutation is in flight (between START and DONE).
#define KECCAK_DATA_21_REG_OFFSET 0xb0

// Word i (0-24) of the 1600-bit Keccak state. This is the permutation
// engine's own working storage -- not a staging/mirror copy -- so it must
// not be written while a permutation is in flight (between START and DONE).
#define KECCAK_DATA_22_REG_OFFSET 0xb8

// Word i (0-24) of the 1600-bit Keccak state. This is the permutation
// engine's own working storage -- not a staging/mirror copy -- so it must
// not be written while a permutation is in flight (between START and DONE).
#define KECCAK_DATA_23_REG_OFFSET 0xc0

// Word i (0-24) of the 1600-bit Keccak state. This is the permutation
// engine's own working storage -- not a staging/mirror copy -- so it must
// not be written while a permutation is in flight (between START and DONE).
#define KECCAK_DATA_24_REG_OFFSET 0xc8

#ifdef __cplusplus
}  // extern "C"
#endif
#endif  // _KECCAK_REG_DEFS_
// End generated register defines for keccak