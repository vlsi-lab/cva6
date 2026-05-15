# =============================================================================
# hash_coproc.S - native RV64 wrappers for the new HASH coprocessor ISA
#
# This file replaces every HORCRUX `keccak_coproc.S`.  The legacy code targeted
# the 32-bit HORCRUX register file (50 x 32-bit lanes) on opcode 0x6b/0x3b.
# The new HASH IP exposes a 25 x 64-bit lane file on opcode 0x5b and stalls
# `issue_ready` until each multi-cycle op finishes, so no NOP padding is
# required.
#
# Exported symbols match the names used by the ported HORCRUX C/H sources:
#
#   void     keccak_hw_init(void);
#   void     keccak_hw_absorb_xor(uint32_t lo, uint32_t hi, uint32_t idx32);
#   void     keccak_hw_permute(void);
#   uint32_t keccak_hw_store_word(uint32_t idx32);
#   uint32_t keccak_hw_read3(uint32_t byte_off);
#   void     cus_load(uint32_t lo, uint32_t hi, uint32_t idx32);
#   uint32_t cus_store(uint32_t idx32);
#   void     keccak_coproc_S(uint32_t *state);  /* 50-word load/permute/store */
#
# Per-test extra entry points (thash1_hw_compute, thash2_hw_compute,
# prf_addr_hw_compute) live in the per-test `hash_ops.S` siblings.
#
# Encoding map (opcode 0x5b):
#   INIT    f3=0 f7=0x00
#   KSTART  f3=0 f7=0x01
#   KPERM   f3=0 f7=0x02
#   LOAD    f3=1 f7=0x00 rs1=data64 rs2=lane_idx
#   KABSORB f3=1 f7=0x01 rs1=data64 rs2=lane_idx
#   STORE   f3=2 f7=0x00 rd=lane    rs1=lane_idx
#   KREAD3  f3=2 f7=0x01 rd=word    rs1=byte_off
# =============================================================================

.section .text
.global keccak_hw_init
.global keccak_hw_absorb_xor
.global keccak_hw_permute
.global keccak_hw_store_word
.global keccak_hw_read3
.global cus_load
.global cus_store
.global keccak_coproc_S
.align 4

# ---------------- low-level instruction macros ----------------

.macro HASH_INIT
    .insn r 0x5b, 0, 0x00, x0, x0, x0
.endm

.macro HASH_KSTART
    .insn r 0x5b, 0, 0x01, x0, x0, x0
.endm

.macro HASH_KPERM
    .insn r 0x5b, 0, 0x02, x0, x0, x0
.endm

.macro HASH_LOAD rs_data, rs_idx
    .insn r 0x5b, 1, 0x00, x0, \rs_data, \rs_idx
.endm

.macro HASH_KABSORB rs_data, rs_idx
    .insn r 0x5b, 1, 0x01, x0, \rs_data, \rs_idx
.endm

.macro HASH_STORE rd, rs_idx
    .insn r 0x5b, 2, 0x00, \rd, \rs_idx, x0
.endm

.macro HASH_KREAD3 rd, rs_off
    .insn r 0x5b, 2, 0x01, \rd, \rs_off, x0
.endm

# ---------------- helpers ----------------

# Pack a HORCRUX (lo32, hi32) pair into a single 64-bit lane in t3.
# Inputs:  a0 = lo (sign-extended 32b), a1 = hi (sign-extended 32b)
# Outputs: t3 = (hi << 32) | (lo & 0xFFFFFFFF)
# Clobbers: t3, t4
.macro PACK_LO_HI
    slli    t3, a0, 32          # zero-extend lo: t3 = lo << 32
    srli    t3, t3, 32          # t3 = lo & 0xFFFFFFFF
    slli    t4, a1, 32          # t4 = hi << 32
    or      t3, t3, t4
.endm

# ============================================================================
# void cus_load(uint32_t lo, uint32_t hi, uint32_t idx32);
#   - Old API wrote lo->reg[idx32] and hi->reg[idx32+1] in 32-bit space.
#   - Maps to a single 64-bit OP_LOAD into lane (idx32 >> 1).
# ============================================================================
cus_load:
    PACK_LO_HI
    srli    t5, a2, 1           # lane index = idx32 / 2
    HASH_LOAD t3, t5
    ret

# ============================================================================
# uint32_t cus_store(uint32_t idx32);
#   - Old API returned the 32-bit word reg[idx32].
#   - Reads the full 64-bit lane and selects the half by parity of idx32.
# ============================================================================
cus_store:
    srli    t5, a0, 1           # lane index
    HASH_STORE t3, t5           # t3 = full 64-bit lane
    andi    t6, a0, 1
    beqz    t6, 1f
    srli    a0, t3, 32          # high half
    ret
1:  slli    a0, t3, 32          # zero-extend low half
    srli    a0, a0, 32
    ret

# ============================================================================
# void keccak_hw_init(void);
# ============================================================================
keccak_hw_init:
    HASH_INIT
    ret

# ============================================================================
# void keccak_hw_absorb_xor(uint32_t lo, uint32_t hi, uint32_t idx32);
# ============================================================================
keccak_hw_absorb_xor:
    PACK_LO_HI
    srli    t5, a2, 1
    HASH_KABSORB t3, t5
    ret

# ============================================================================
# void keccak_hw_permute(void);
#   - Single Keccak-f[1600] in place.  No NOPs needed: issue_ready is held
#     low by hash_xif_ex until the permutation completes.
# ============================================================================
keccak_hw_permute:
    HASH_KPERM
    ret

# ============================================================================
# uint32_t keccak_hw_store_word(uint32_t idx32);
# ============================================================================
keccak_hw_store_word:
    j       cus_store           # identical semantics

# ============================================================================
# uint32_t keccak_hw_read3(uint32_t byte_off);
#   - Returns the low 24 bits at byte offset byte_off; upper bits zero.
# ============================================================================
keccak_hw_read3:
    HASH_KREAD3 a0, a0
    li      t0, 0x00FFFFFF
    and     a0, a0, t0
    ret

# ============================================================================
# void keccak_coproc_S(uint32_t *state);
#   - Legacy whole-state load/permute/store helper.
#   - Loads 50 32-bit words from `state` into 25 64-bit lanes, runs one
#     permutation, then writes the result back.
# ============================================================================
keccak_coproc_S:
    addi    sp, sp, -8
    sd      ra, 0(sp)

    li      t0, 0               # 64-bit lane index (0..24)
    mv      t1, a0              # word pointer

1:  # Load lane t0 from words [t1+0]:[t1+4]
    lwu     t2, 0(t1)           # lo (zero-extended)
    lwu     t3, 4(t1)           # hi (zero-extended)
    slli    t3, t3, 32
    or      t3, t2, t3
    HASH_LOAD t3, t0
    addi    t0, t0, 1
    addi    t1, t1, 8
    li      t2, 25
    blt     t0, t2, 1b

    HASH_KPERM

    li      t0, 0
    mv      t1, a0
2:  HASH_STORE t3, t0
    sw      t3, 0(t1)           # low 32 bits
    srli    t4, t3, 32
    sw      t4, 4(t1)           # high 32 bits
    addi    t0, t0, 1
    addi    t1, t1, 8
    li      t2, 25
    blt     t0, t2, 2b

    ld      ra, 0(sp)
    addi    sp, sp, 8
    ret
