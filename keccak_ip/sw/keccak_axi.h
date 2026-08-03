// Generated register defines for keccak

#ifndef _KECCAK_REG_DEFS_
#define _KECCAK_REG_DEFS_

#ifdef __cplusplus
extern "C" {
#endif
// Register width
#define KECCAK_PARAM_REG_WIDTH 64

// I/O cryptographic state register of the Keccak AXI Accellerator (common
// parameters)
#define KECCAK_DATA_DATA_FIELD_WIDTH 64
#define KECCAK_DATA_DATA_FIELDS_PER_REG 1
#define KECCAK_DATA_MULTIREG_COUNT 25

// I/O cryptographic state register of the Keccak AXI Accellerator
#define KECCAK_DATA_0_REG_OFFSET 0x0

// I/O cryptographic state register of the Keccak AXI Accellerator
#define KECCAK_DATA_1_REG_OFFSET 0x8

// I/O cryptographic state register of the Keccak AXI Accellerator
#define KECCAK_DATA_2_REG_OFFSET 0x10

// I/O cryptographic state register of the Keccak AXI Accellerator
#define KECCAK_DATA_3_REG_OFFSET 0x18

// I/O cryptographic state register of the Keccak AXI Accellerator
#define KECCAK_DATA_4_REG_OFFSET 0x20

// I/O cryptographic state register of the Keccak AXI Accellerator
#define KECCAK_DATA_5_REG_OFFSET 0x28

// I/O cryptographic state register of the Keccak AXI Accellerator
#define KECCAK_DATA_6_REG_OFFSET 0x30

// I/O cryptographic state register of the Keccak AXI Accellerator
#define KECCAK_DATA_7_REG_OFFSET 0x38

// I/O cryptographic state register of the Keccak AXI Accellerator
#define KECCAK_DATA_8_REG_OFFSET 0x40

// I/O cryptographic state register of the Keccak AXI Accellerator
#define KECCAK_DATA_9_REG_OFFSET 0x48

// I/O cryptographic state register of the Keccak AXI Accellerator
#define KECCAK_DATA_10_REG_OFFSET 0x50

// I/O cryptographic state register of the Keccak AXI Accellerator
#define KECCAK_DATA_11_REG_OFFSET 0x58

// I/O cryptographic state register of the Keccak AXI Accellerator
#define KECCAK_DATA_12_REG_OFFSET 0x60

// I/O cryptographic state register of the Keccak AXI Accellerator
#define KECCAK_DATA_13_REG_OFFSET 0x68

// I/O cryptographic state register of the Keccak AXI Accellerator
#define KECCAK_DATA_14_REG_OFFSET 0x70

// I/O cryptographic state register of the Keccak AXI Accellerator
#define KECCAK_DATA_15_REG_OFFSET 0x78

// I/O cryptographic state register of the Keccak AXI Accellerator
#define KECCAK_DATA_16_REG_OFFSET 0x80

// I/O cryptographic state register of the Keccak AXI Accellerator
#define KECCAK_DATA_17_REG_OFFSET 0x88

// I/O cryptographic state register of the Keccak AXI Accellerator
#define KECCAK_DATA_18_REG_OFFSET 0x90

// I/O cryptographic state register of the Keccak AXI Accellerator
#define KECCAK_DATA_19_REG_OFFSET 0x98

// I/O cryptographic state register of the Keccak AXI Accellerator
#define KECCAK_DATA_20_REG_OFFSET 0xa0

// I/O cryptographic state register of the Keccak AXI Accellerator
#define KECCAK_DATA_21_REG_OFFSET 0xa8

// I/O cryptographic state register of the Keccak AXI Accellerator
#define KECCAK_DATA_22_REG_OFFSET 0xb0

// I/O cryptographic state register of the Keccak AXI Accellerator
#define KECCAK_DATA_23_REG_OFFSET 0xb8

// I/O cryptographic state register of the Keccak AXI Accellerator
#define KECCAK_DATA_24_REG_OFFSET 0xc0

// Control and status register for Keccak AXI Accellerator
#define KECCAK_CSREG_REG_OFFSET 0xc8
#define KECCAK_CSREG_START_BIT 0
#define KECCAK_CSREG_DONE_BIT 1

// Physical address of raw input bytes for the DMA-driven absorb job
#define KECCAK_JOB_SRC_ADDR_REG_OFFSET 0xd0

// Number of bytes to DMA-absorb from JOB_SRC_ADDR
#define KECCAK_JOB_SRC_LEN_REG_OFFSET 0xd8
#define KECCAK_JOB_SRC_LEN_JOB_SRC_LEN_MASK 0xffffffff
#define KECCAK_JOB_SRC_LEN_JOB_SRC_LEN_OFFSET 0
#define KECCAK_JOB_SRC_LEN_JOB_SRC_LEN_FIELD \
  ((bitfield_field32_t) { .mask = KECCAK_JOB_SRC_LEN_JOB_SRC_LEN_MASK, .index = KECCAK_JOB_SRC_LEN_JOB_SRC_LEN_OFFSET })

// Physical address to DMA-squeeze output bytes into
#define KECCAK_JOB_DST_ADDR_REG_OFFSET 0xe0

// Number of bytes to DMA-squeeze into JOB_DST_ADDR
#define KECCAK_JOB_DST_LEN_REG_OFFSET 0xe8
#define KECCAK_JOB_DST_LEN_JOB_DST_LEN_MASK 0xffffffff
#define KECCAK_JOB_DST_LEN_JOB_DST_LEN_OFFSET 0
#define KECCAK_JOB_DST_LEN_JOB_DST_LEN_FIELD \
  ((bitfield_field32_t) { .mask = KECCAK_JOB_DST_LEN_JOB_DST_LEN_MASK, .index = KECCAK_JOB_DST_LEN_JOB_DST_LEN_OFFSET })

// DMA job descriptor control and status
#define KECCAK_JOBCTRL_REG_OFFSET 0xf0
#define KECCAK_JOBCTRL_GO_BIT 0
#define KECCAK_JOBCTRL_FRESH_BIT 1
#define KECCAK_JOBCTRL_FLIP_BIT 2
#define KECCAK_JOBCTRL_DONE_BIT 3
#define KECCAK_JOBCTRL_DPTR_MASK 0xff
#define KECCAK_JOBCTRL_DPTR_OFFSET 4
#define KECCAK_JOBCTRL_DPTR_FIELD \
  ((bitfield_field32_t) { .mask = KECCAK_JOBCTRL_DPTR_MASK, .index = KECCAK_JOBCTRL_DPTR_OFFSET })

// Physical base address of the uint32_t polynomial array a[] (mp_NTT/mp_iNTT
// operand, updated in place)
#define KECCAK_NTT_A_ADDR_REG_OFFSET 0xf8

// Physical base address of the uint32_t twiddle table (gm[] for forward
// NTT_CTRL.MODE=0, igm[] for inverse NTT_CTRL.MODE=1 -- caller points this
// at whichever mp_mkgm/mp_mkigm table the job needs)
#define KECCAK_NTT_GM_ADDR_REG_OFFSET 0x100

// Degree parameter (log2 n; matches mp_NTT/mp_iNTT's logn argument, n = 1 <<
// logn)
#define KECCAK_NTT_LOGN_REG_OFFSET 0x108
#define KECCAK_NTT_LOGN_NTT_LOGN_MASK 0x1f
#define KECCAK_NTT_LOGN_NTT_LOGN_OFFSET 0
#define KECCAK_NTT_LOGN_NTT_LOGN_FIELD \
  ((bitfield_field32_t) { .mask = KECCAK_NTT_LOGN_NTT_LOGN_MASK, .index = KECCAK_NTT_LOGN_NTT_LOGN_OFFSET })

// Modulus p for this job (any usable prime -- software supplies it directly,
// matching mp_NTT/mp_iNTT's own p argument, instead of the accelerator
// hardcoding a fixed prime table)
#define KECCAK_NTT_P_VAL_REG_OFFSET 0x110
#define KECCAK_NTT_P_VAL_NTT_P_VAL_MASK 0xffffffff
#define KECCAK_NTT_P_VAL_NTT_P_VAL_OFFSET 0
#define KECCAK_NTT_P_VAL_NTT_P_VAL_FIELD \
  ((bitfield_field32_t) { .mask = KECCAK_NTT_P_VAL_NTT_P_VAL_MASK, .index = KECCAK_NTT_P_VAL_NTT_P_VAL_OFFSET })

// p0i = -1/p mod 2^32 for this job, software-precomputed exactly as
// mp_NTT/mp_iNTT's own p0i argument (e.g. from the PRIMES[] table)
#define KECCAK_NTT_P0I_VAL_REG_OFFSET 0x118
#define KECCAK_NTT_P0I_VAL_NTT_P0I_VAL_MASK 0xffffffff
#define KECCAK_NTT_P0I_VAL_NTT_P0I_VAL_OFFSET 0
#define KECCAK_NTT_P0I_VAL_NTT_P0I_VAL_FIELD \
  ((bitfield_field32_t) { .mask = KECCAK_NTT_P0I_VAL_NTT_P0I_VAL_MASK, .index = KECCAK_NTT_P0I_VAL_NTT_P0I_VAL_OFFSET })

// NTT/iNTT accelerator job control and status
#define KECCAK_NTT_CTRL_REG_OFFSET 0x120
#define KECCAK_NTT_CTRL_GO_BIT 0
#define KECCAK_NTT_CTRL_DONE_BIT 1
#define KECCAK_NTT_CTRL_MODE_BIT 2

// Physical base address of the uint16_t output sample array for the
// rejection-sampler job (Falcon's Zf(hash_to_point_vartime), common.c)
#define KECCAK_REJ_X_ADDR_REG_OFFSET 0x128

// Rejection-sampler job parameters, packed to keep the register count small:
// Q (modulus, bits 15:0), THRESH (rejection bound, bits 31:16), N (accepted-
// sample target, bits 63:32)
#define KECCAK_REJ_PARAMS_REG_OFFSET 0x130
#define KECCAK_REJ_PARAMS_Q_MASK 0xffff
#define KECCAK_REJ_PARAMS_Q_OFFSET 0
#define KECCAK_REJ_PARAMS_Q_FIELD \
  ((bitfield_field32_t) { .mask = KECCAK_REJ_PARAMS_Q_MASK, .index = KECCAK_REJ_PARAMS_Q_OFFSET })
#define KECCAK_REJ_PARAMS_THRESH_MASK 0xffff
#define KECCAK_REJ_PARAMS_THRESH_OFFSET 16
#define KECCAK_REJ_PARAMS_THRESH_FIELD \
  ((bitfield_field32_t) { .mask = KECCAK_REJ_PARAMS_THRESH_MASK, .index = KECCAK_REJ_PARAMS_THRESH_OFFSET })
#define KECCAK_REJ_PARAMS_N_MASK 0xffffffff
#define KECCAK_REJ_PARAMS_N_OFFSET 32
#define KECCAK_REJ_PARAMS_N_FIELD \
  ((bitfield_field32_t) { .mask = KECCAK_REJ_PARAMS_N_MASK, .index = KECCAK_REJ_PARAMS_N_OFFSET })

// Rejection-sampler job control and status. Requires the accelerator's
// DATA[] state to already be hardware-resident and shake_flip()-padded (not
// yet permuted) for the calling shake context before GO is set.
#define KECCAK_REJ_CTRL_REG_OFFSET 0x138
#define KECCAK_REJ_CTRL_GO_BIT 0
#define KECCAK_REJ_CTRL_DONE_BIT 1

#ifdef __cplusplus
}  // extern "C"
#endif
#endif  // _KECCAK_REG_DEFS_
// End generated register defines for keccak