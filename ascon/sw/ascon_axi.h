// Generated register defines for ascon

#ifndef _ASCON_REG_DEFS_
#define _ASCON_REG_DEFS_

#ifdef __cplusplus
extern "C" {
#endif
// Register width
#define ASCON_PARAM_REG_WIDTH 64

// I/O 320-bit Ascon state register (5 x 64-bit lanes x0..x4) (common
// parameters)
#define ASCON_DATA_DATA_FIELD_WIDTH 64
#define ASCON_DATA_DATA_FIELDS_PER_REG 1
#define ASCON_DATA_MULTIREG_COUNT 5

// I/O 320-bit Ascon state register (5 x 64-bit lanes x0..x4)
#define ASCON_DATA_0_REG_OFFSET 0x0

// I/O 320-bit Ascon state register (5 x 64-bit lanes x0..x4)
#define ASCON_DATA_1_REG_OFFSET 0x8

// I/O 320-bit Ascon state register (5 x 64-bit lanes x0..x4)
#define ASCON_DATA_2_REG_OFFSET 0x10

// I/O 320-bit Ascon state register (5 x 64-bit lanes x0..x4)
#define ASCON_DATA_3_REG_OFFSET 0x18

// I/O 320-bit Ascon state register (5 x 64-bit lanes x0..x4)
#define ASCON_DATA_4_REG_OFFSET 0x20

// Control and status register for the Ascon accelerator
#define ASCON_CSREG_REG_OFFSET 0x28
#define ASCON_CSREG_START_BIT 0
#define ASCON_CSREG_DONE_BIT 1
#define ASCON_CSREG_ROUNDS_MASK 0xf
#define ASCON_CSREG_ROUNDS_OFFSET 2
#define ASCON_CSREG_ROUNDS_FIELD \
  ((bitfield_field32_t) { .mask = ASCON_CSREG_ROUNDS_MASK, .index = ASCON_CSREG_ROUNDS_OFFSET })

#ifdef __cplusplus
}  // extern "C"
#endif
#endif  // _ASCON_REG_DEFS_
// End generated register defines for ascon