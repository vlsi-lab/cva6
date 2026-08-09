// Generated register defines for vrf

#ifndef _VRF_REG_DEFS_
#define _VRF_REG_DEFS_

#ifdef __cplusplus
extern "C" {
#endif
// Register width
#define VRF_PARAM_REG_WIDTH 64

// I/O cryptographic state register of the VRF AXI Accellerator (common
// parameters)
#define VRF_DATA_DATA_FIELD_WIDTH 64
#define VRF_DATA_DATA_FIELDS_PER_REG 1
#define VRF_DATA_MULTIREG_COUNT 25

// I/O cryptographic state register of the VRF AXI Accellerator
#define VRF_DATA_0_REG_OFFSET 0x0

// I/O cryptographic state register of the VRF AXI Accellerator
#define VRF_DATA_1_REG_OFFSET 0x8

// I/O cryptographic state register of the VRF AXI Accellerator
#define VRF_DATA_2_REG_OFFSET 0x10

// I/O cryptographic state register of the VRF AXI Accellerator
#define VRF_DATA_3_REG_OFFSET 0x18

// I/O cryptographic state register of the VRF AXI Accellerator
#define VRF_DATA_4_REG_OFFSET 0x20

// I/O cryptographic state register of the VRF AXI Accellerator
#define VRF_DATA_5_REG_OFFSET 0x28

// I/O cryptographic state register of the VRF AXI Accellerator
#define VRF_DATA_6_REG_OFFSET 0x30

// I/O cryptographic state register of the VRF AXI Accellerator
#define VRF_DATA_7_REG_OFFSET 0x38

// I/O cryptographic state register of the VRF AXI Accellerator
#define VRF_DATA_8_REG_OFFSET 0x40

// I/O cryptographic state register of the VRF AXI Accellerator
#define VRF_DATA_9_REG_OFFSET 0x48

// I/O cryptographic state register of the VRF AXI Accellerator
#define VRF_DATA_10_REG_OFFSET 0x50

// I/O cryptographic state register of the VRF AXI Accellerator
#define VRF_DATA_11_REG_OFFSET 0x58

// I/O cryptographic state register of the VRF AXI Accellerator
#define VRF_DATA_12_REG_OFFSET 0x60

// I/O cryptographic state register of the VRF AXI Accellerator
#define VRF_DATA_13_REG_OFFSET 0x68

// I/O cryptographic state register of the VRF AXI Accellerator
#define VRF_DATA_14_REG_OFFSET 0x70

// I/O cryptographic state register of the VRF AXI Accellerator
#define VRF_DATA_15_REG_OFFSET 0x78

// I/O cryptographic state register of the VRF AXI Accellerator
#define VRF_DATA_16_REG_OFFSET 0x80

// I/O cryptographic state register of the VRF AXI Accellerator
#define VRF_DATA_17_REG_OFFSET 0x88

// I/O cryptographic state register of the VRF AXI Accellerator
#define VRF_DATA_18_REG_OFFSET 0x90

// I/O cryptographic state register of the VRF AXI Accellerator
#define VRF_DATA_19_REG_OFFSET 0x98

// I/O cryptographic state register of the VRF AXI Accellerator
#define VRF_DATA_20_REG_OFFSET 0xa0

// I/O cryptographic state register of the VRF AXI Accellerator
#define VRF_DATA_21_REG_OFFSET 0xa8

// I/O cryptographic state register of the VRF AXI Accellerator
#define VRF_DATA_22_REG_OFFSET 0xb0

// I/O cryptographic state register of the VRF AXI Accellerator
#define VRF_DATA_23_REG_OFFSET 0xb8

// I/O cryptographic state register of the VRF AXI Accellerator
#define VRF_DATA_24_REG_OFFSET 0xc0

// Control and status register for VRF AXI Accellerator
#define VRF_CSREG_REG_OFFSET 0xc8
#define VRF_CSREG_START_BIT 0
#define VRF_CSREG_DONE_BIT 1

// Physical address of raw input bytes for the DMA-driven absorb job
#define VRF_JOB_SRC_ADDR_REG_OFFSET 0xd0

// Number of bytes to DMA-absorb from JOB_SRC_ADDR
#define VRF_JOB_SRC_LEN_REG_OFFSET 0xd8
#define VRF_JOB_SRC_LEN_JOB_SRC_LEN_MASK 0xffffffff
#define VRF_JOB_SRC_LEN_JOB_SRC_LEN_OFFSET 0
#define VRF_JOB_SRC_LEN_JOB_SRC_LEN_FIELD \
  ((bitfield_field32_t) { .mask = VRF_JOB_SRC_LEN_JOB_SRC_LEN_MASK, .index = VRF_JOB_SRC_LEN_JOB_SRC_LEN_OFFSET })

// Physical address to DMA-squeeze output bytes into
#define VRF_JOB_DST_ADDR_REG_OFFSET 0xe0

// Number of bytes to DMA-squeeze into JOB_DST_ADDR
#define VRF_JOB_DST_LEN_REG_OFFSET 0xe8
#define VRF_JOB_DST_LEN_JOB_DST_LEN_MASK 0xffffffff
#define VRF_JOB_DST_LEN_JOB_DST_LEN_OFFSET 0
#define VRF_JOB_DST_LEN_JOB_DST_LEN_FIELD \
  ((bitfield_field32_t) { .mask = VRF_JOB_DST_LEN_JOB_DST_LEN_MASK, .index = VRF_JOB_DST_LEN_JOB_DST_LEN_OFFSET })

// DMA job descriptor control and status
#define VRF_JOBCTRL_REG_OFFSET 0xf0
#define VRF_JOBCTRL_GO_BIT 0
#define VRF_JOBCTRL_FRESH_BIT 1
#define VRF_JOBCTRL_FLIP_BIT 2
#define VRF_JOBCTRL_DONE_BIT 3
#define VRF_JOBCTRL_DPTR_MASK 0xff
#define VRF_JOBCTRL_DPTR_OFFSET 4
#define VRF_JOBCTRL_DPTR_FIELD \
  ((bitfield_field32_t) { .mask = VRF_JOBCTRL_DPTR_MASK, .index = VRF_JOBCTRL_DPTR_OFFSET })
#define VRF_JOBCTRL_RATE168_BIT 12

// Physical base address of the uint32_t polynomial array a[] (mp_NTT/mp_iNTT
// operand, updated in place)
#define VRF_NTT_A_ADDR_REG_OFFSET 0xf8

// Physical base address of the uint32_t twiddle table (gm[] for forward
// NTT_CTRL.MODE=0, igm[] for inverse NTT_CTRL.MODE=1 -- caller points this
// at whichever mp_mkgm/mp_mkigm table the job needs)
#define VRF_NTT_GM_ADDR_REG_OFFSET 0x100

// Degree parameter (log2 n; matches mp_NTT/mp_iNTT's logn argument, n = 1 <<
// logn)
#define VRF_NTT_LOGN_REG_OFFSET 0x108
#define VRF_NTT_LOGN_NTT_LOGN_MASK 0x1f
#define VRF_NTT_LOGN_NTT_LOGN_OFFSET 0
#define VRF_NTT_LOGN_NTT_LOGN_FIELD \
  ((bitfield_field32_t) { .mask = VRF_NTT_LOGN_NTT_LOGN_MASK, .index = VRF_NTT_LOGN_NTT_LOGN_OFFSET })

// Modulus p for this job (any usable prime -- software supplies it directly,
// matching mp_NTT/mp_iNTT's own p argument, instead of the accelerator
// hardcoding a fixed prime table)
#define VRF_NTT_P_VAL_REG_OFFSET 0x110
#define VRF_NTT_P_VAL_NTT_P_VAL_MASK 0xffffffff
#define VRF_NTT_P_VAL_NTT_P_VAL_OFFSET 0
#define VRF_NTT_P_VAL_NTT_P_VAL_FIELD \
  ((bitfield_field32_t) { .mask = VRF_NTT_P_VAL_NTT_P_VAL_MASK, .index = VRF_NTT_P_VAL_NTT_P_VAL_OFFSET })

// p0i = -1/p mod 2^32 for this job, software-precomputed exactly as
// mp_NTT/mp_iNTT's own p0i argument (e.g. from the PRIMES[] table)
#define VRF_NTT_P0I_VAL_REG_OFFSET 0x118
#define VRF_NTT_P0I_VAL_NTT_P0I_VAL_MASK 0xffffffff
#define VRF_NTT_P0I_VAL_NTT_P0I_VAL_OFFSET 0
#define VRF_NTT_P0I_VAL_NTT_P0I_VAL_FIELD \
  ((bitfield_field32_t) { .mask = VRF_NTT_P0I_VAL_NTT_P0I_VAL_MASK, .index = VRF_NTT_P0I_VAL_NTT_P0I_VAL_OFFSET })

// NTT/iNTT accelerator job control and status
#define VRF_NTT_CTRL_REG_OFFSET 0x120
#define VRF_NTT_CTRL_GO_BIT 0
#define VRF_NTT_CTRL_DONE_BIT 1
#define VRF_NTT_CTRL_MODE_BIT 2
#define VRF_NTT_CTRL_NOSCALE_BIT 3

// Physical base address of the output sample array for the rejection-sampler
// job (element width per REJ_CTRL.OUTWIDE): uint16_t for Falcon's
// Zf(hash_to_point_vartime) (common.c), int32_t for ML-DSA's rej_uniform
// (poly.c)
#define VRF_REJ_X_ADDR_REG_OFFSET 0x128

// Rejection-sampler job parameters, packed to keep the register count small:
// Q (modulus, bits 23:0), THRESH (rejection bound, bits 47:24), N (accepted-
// sample target, bits 63:48)
#define VRF_REJ_PARAMS_REG_OFFSET 0x130
#define VRF_REJ_PARAMS_Q_MASK 0xffffff
#define VRF_REJ_PARAMS_Q_OFFSET 0
#define VRF_REJ_PARAMS_Q_FIELD \
  ((bitfield_field32_t) { .mask = VRF_REJ_PARAMS_Q_MASK, .index = VRF_REJ_PARAMS_Q_OFFSET })
#define VRF_REJ_PARAMS_THRESH_MASK 0xffffff
#define VRF_REJ_PARAMS_THRESH_OFFSET 24
#define VRF_REJ_PARAMS_THRESH_FIELD \
  ((bitfield_field32_t) { .mask = VRF_REJ_PARAMS_THRESH_MASK, .index = VRF_REJ_PARAMS_THRESH_OFFSET })
#define VRF_REJ_PARAMS_N_MASK 0xffff
#define VRF_REJ_PARAMS_N_OFFSET 48
#define VRF_REJ_PARAMS_N_FIELD \
  ((bitfield_field32_t) { .mask = VRF_REJ_PARAMS_N_MASK, .index = VRF_REJ_PARAMS_N_OFFSET })

// Rejection-sampler job control and status. Requires the accelerator's
// DATA[] state to already be hardware-resident and shake_flip()-padded (not
// yet permuted) for the calling shake context before GO is set.
#define VRF_REJ_CTRL_REG_OFFSET 0x138
#define VRF_REJ_CTRL_GO_BIT 0
#define VRF_REJ_CTRL_DONE_BIT 1
#define VRF_REJ_CTRL_CAND3_BIT 2
#define VRF_REJ_CTRL_RATE168_BIT 3
#define VRF_REJ_CTRL_OUTWIDE_BIT 4

// SPHINCS+/SLH-DSA SHAKE256 hash-chain job pub_seed input (32 bytes, word i
// = bytes [8i..8i+7], byte 8i at bits [7:0]) (common parameters)
#define VRF_CHAIN_SEED_CHAIN_SEED_FIELD_WIDTH 64
#define VRF_CHAIN_SEED_CHAIN_SEED_FIELDS_PER_REG 1
#define VRF_CHAIN_SEED_MULTIREG_COUNT 4

// SPHINCS+/SLH-DSA SHAKE256 hash-chain job pub_seed input (32 bytes, word i
// = bytes [8i..8i+7], byte 8i at bits [7:0])
#define VRF_CHAIN_SEED_0_REG_OFFSET 0x140

// SPHINCS+/SLH-DSA SHAKE256 hash-chain job pub_seed input (32 bytes, word i
// = bytes [8i..8i+7], byte 8i at bits [7:0])
#define VRF_CHAIN_SEED_1_REG_OFFSET 0x148

// SPHINCS+/SLH-DSA SHAKE256 hash-chain job pub_seed input (32 bytes, word i
// = bytes [8i..8i+7], byte 8i at bits [7:0])
#define VRF_CHAIN_SEED_2_REG_OFFSET 0x150

// SPHINCS+/SLH-DSA SHAKE256 hash-chain job pub_seed input (32 bytes, word i
// = bytes [8i..8i+7], byte 8i at bits [7:0])
#define VRF_CHAIN_SEED_3_REG_OFFSET 0x158

// SPHINCS+/SLH-DSA SHAKE256 hash-chain job full 32-byte ADRS input (word i =
// bytes [8i..8i+7], byte 8i at bits [7:0]) (common parameters)
#define VRF_CHAIN_ADRS_CHAIN_ADRS_FIELD_WIDTH 64
#define VRF_CHAIN_ADRS_CHAIN_ADRS_FIELDS_PER_REG 1
#define VRF_CHAIN_ADRS_MULTIREG_COUNT 4

// SPHINCS+/SLH-DSA SHAKE256 hash-chain job full 32-byte ADRS input (word i =
// bytes [8i..8i+7], byte 8i at bits [7:0])
#define VRF_CHAIN_ADRS_0_REG_OFFSET 0x160

// SPHINCS+/SLH-DSA SHAKE256 hash-chain job full 32-byte ADRS input (word i =
// bytes [8i..8i+7], byte 8i at bits [7:0])
#define VRF_CHAIN_ADRS_1_REG_OFFSET 0x168

// SPHINCS+/SLH-DSA SHAKE256 hash-chain job full 32-byte ADRS input (word i =
// bytes [8i..8i+7], byte 8i at bits [7:0])
#define VRF_CHAIN_ADRS_2_REG_OFFSET 0x170

// SPHINCS+/SLH-DSA SHAKE256 hash-chain job full 32-byte ADRS input (word i =
// bytes [8i..8i+7], byte 8i at bits [7:0])
#define VRF_CHAIN_ADRS_3_REG_OFFSET 0x178

// SPHINCS+/SLH-DSA SHAKE256 hash-chain job THASH2 second input block
// (input_block2, 32 bytes, word i = bytes [8i..8i+7], byte 8i at bits [7:0])
// (common parameters)
#define VRF_CHAIN_IN2_CHAIN_IN2_FIELD_WIDTH 64
#define VRF_CHAIN_IN2_CHAIN_IN2_FIELDS_PER_REG 1
#define VRF_CHAIN_IN2_MULTIREG_COUNT 4

// SPHINCS+/SLH-DSA SHAKE256 hash-chain job THASH2 second input block
// (input_block2, 32 bytes, word i = bytes [8i..8i+7], byte 8i at bits [7:0])
#define VRF_CHAIN_IN2_0_REG_OFFSET 0x180

// SPHINCS+/SLH-DSA SHAKE256 hash-chain job THASH2 second input block
// (input_block2, 32 bytes, word i = bytes [8i..8i+7], byte 8i at bits [7:0])
#define VRF_CHAIN_IN2_1_REG_OFFSET 0x188

// SPHINCS+/SLH-DSA SHAKE256 hash-chain job THASH2 second input block
// (input_block2, 32 bytes, word i = bytes [8i..8i+7], byte 8i at bits [7:0])
#define VRF_CHAIN_IN2_2_REG_OFFSET 0x190

// SPHINCS+/SLH-DSA SHAKE256 hash-chain job THASH2 second input block
// (input_block2, 32 bytes, word i = bytes [8i..8i+7], byte 8i at bits [7:0])
#define VRF_CHAIN_IN2_3_REG_OFFSET 0x198

// SPHINCS+/SLH-DSA SHAKE256 hash-chain job input_block1
// (THASH1/THASH2/PRF_ADDR) before GO, and output digest after DONE (32
// bytes, word i = bytes [8i..8i+7], byte 8i at bits [7:0]) (common
// parameters)
#define VRF_CHAIN_IO_CHAIN_IO_FIELD_WIDTH 64
#define VRF_CHAIN_IO_CHAIN_IO_FIELDS_PER_REG 1
#define VRF_CHAIN_IO_MULTIREG_COUNT 4

// SPHINCS+/SLH-DSA SHAKE256 hash-chain job input_block1
// (THASH1/THASH2/PRF_ADDR) before GO, and output digest after DONE (32
// bytes, word i = bytes [8i..8i+7], byte 8i at bits [7:0])
#define VRF_CHAIN_IO_0_REG_OFFSET 0x1a0

// SPHINCS+/SLH-DSA SHAKE256 hash-chain job input_block1
// (THASH1/THASH2/PRF_ADDR) before GO, and output digest after DONE (32
// bytes, word i = bytes [8i..8i+7], byte 8i at bits [7:0])
#define VRF_CHAIN_IO_1_REG_OFFSET 0x1a8

// SPHINCS+/SLH-DSA SHAKE256 hash-chain job input_block1
// (THASH1/THASH2/PRF_ADDR) before GO, and output digest after DONE (32
// bytes, word i = bytes [8i..8i+7], byte 8i at bits [7:0])
#define VRF_CHAIN_IO_2_REG_OFFSET 0x1b0

// SPHINCS+/SLH-DSA SHAKE256 hash-chain job input_block1
// (THASH1/THASH2/PRF_ADDR) before GO, and output digest after DONE (32
// bytes, word i = bytes [8i..8i+7], byte 8i at bits [7:0])
#define VRF_CHAIN_IO_3_REG_OFFSET 0x1b8

// SPHINCS+/SLH-DSA SHAKE256 hash-chain job control and status
#define VRF_CHAIN_CTRL_REG_OFFSET 0x1c0
#define VRF_CHAIN_CTRL_GO_BIT 0
#define VRF_CHAIN_CTRL_DONE_BIT 1
#define VRF_CHAIN_CTRL_ROBUST_BIT 2
#define VRF_CHAIN_CTRL_N_MASK 0xff
#define VRF_CHAIN_CTRL_N_OFFSET 3
#define VRF_CHAIN_CTRL_N_FIELD \
  ((bitfield_field32_t) { .mask = VRF_CHAIN_CTRL_N_MASK, .index = VRF_CHAIN_CTRL_N_OFFSET })
#define VRF_CHAIN_CTRL_STEPS_MASK 0xff
#define VRF_CHAIN_CTRL_STEPS_OFFSET 11
#define VRF_CHAIN_CTRL_STEPS_FIELD \
  ((bitfield_field32_t) { .mask = VRF_CHAIN_CTRL_STEPS_MASK, .index = VRF_CHAIN_CTRL_STEPS_OFFSET })
#define VRF_CHAIN_CTRL_STEP_START_MASK 0xff
#define VRF_CHAIN_CTRL_STEP_START_OFFSET 19
#define VRF_CHAIN_CTRL_STEP_START_FIELD \
  ((bitfield_field32_t) { .mask = VRF_CHAIN_CTRL_STEP_START_MASK, .index = VRF_CHAIN_CTRL_STEP_START_OFFSET })
#define VRF_CHAIN_CTRL_OP_TYPE_MASK 0x3
#define VRF_CHAIN_CTRL_OP_TYPE_OFFSET 27
#define VRF_CHAIN_CTRL_OP_TYPE_FIELD \
  ((bitfield_field32_t) { .mask = VRF_CHAIN_CTRL_OP_TYPE_MASK, .index = VRF_CHAIN_CTRL_OP_TYPE_OFFSET })

#ifdef __cplusplus
}  // extern "C"
#endif
#endif  // _VRF_REG_DEFS_
// End generated register defines for vrf