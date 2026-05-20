# =============================================================================
# keccak_coproc.S - cva6 HASH IP assembly wrappers for SLH-DSA optimizations
#
# This file includes the shared compatibility layer from inc/hash_coproc.S
# (which provides cus_load, cus_store, and keccak functions), then adds
# SPHINCS+-specific operations for thash1/thash2 and PRF addressing.
#
# The new HASH IP uses opcode 0x5b with 64-bit lane addressing.
# =============================================================================

#include "../../../../../inc/hash_coproc.S"

.section .text
.global thash1_hw_compute
.global thash2_hw_compute
.global prf_addr_hw_compute
.global thash1_simple_hw_compute
.global thash2_simple_hw_compute
.global thash1_192_hw_compute
.global thash2_192_hw_compute
.global thash1_192_simple_hw_compute
.global thash2_192_simple_hw_compute
.global prf_192_hw_compute
.global thash1_256_hw_compute
.global thash2_256_hw_compute
.global thash1_256_simple_hw_compute
.global thash2_256_simple_hw_compute
.global prf_256_hw_compute
.align 4

# OP_THASH1: n=16, robust mode (simple_flag=0)
# Encoding: opcode=0x5b, funct3=3, funct7=0x00
thash1_hw_compute:
    .insn r 0x5b, 3, 0x00, x0, x0, x0
    ret

# OP_THASH2: n=16, robust mode (simple_flag=0)
# Encoding: opcode=0x5b, funct3=3, funct7=0x01
thash2_hw_compute:
    .insn r 0x5b, 3, 0x01, x0, x0, x0
    ret

# PRF_ADDR: n=16
# Encoding: opcode=0x5b, funct3=3, funct7=0x02
prf_addr_hw_compute:
    .insn r 0x5b, 3, 0x02, x0, x0, x0
    ret

# THASH1_SIMPLE: n=16, simple mode (simple_flag=1)
# Note: simple flag passed via rs2=1, but for these compact stubs we trigger always
thash1_simple_hw_compute:
    li t0, 1
    .insn r 0x5b, 3, 0x00, x0, x0, t0
    ret

# THASH2_SIMPLE: n=16, simple mode (simple_flag=1)
thash2_simple_hw_compute:
    li t0, 1
    .insn r 0x5b, 3, 0x01, x0, x0, t0
    ret

# OP_THASH1_192: n=24, robust mode
# Encoding: opcode=0x5b, funct3=3, funct7=0x03
thash1_192_hw_compute:
    .insn r 0x5b, 3, 0x03, x0, x0, x0
    ret

# OP_THASH2_192: n=24, robust mode
# Encoding: opcode=0x5b, funct3=3, funct7=0x04
thash2_192_hw_compute:
    .insn r 0x5b, 3, 0x04, x0, x0, x0
    ret

# THASH1_192_SIMPLE: n=24, simple mode
thash1_192_simple_hw_compute:
    li t0, 1
    .insn r 0x5b, 3, 0x03, x0, x0, t0
    ret

# THASH2_192_SIMPLE: n=24, simple mode
thash2_192_simple_hw_compute:
    li t0, 1
    .insn r 0x5b, 3, 0x04, x0, x0, t0
    ret

# PRF_ADDR_192: n=24
# Encoding: opcode=0x5b, funct3=3, funct7=0x07 (per hash_pkg.sv)
prf_192_hw_compute:
    .insn r 0x5b, 3, 0x07, x0, x0, x0
    ret

# OP_THASH1_256: n=32, robust mode
# Encoding: opcode=0x5b, funct3=3, funct7=0x05 (per hash_pkg.sv)
thash1_256_hw_compute:
    .insn r 0x5b, 3, 0x05, x0, x0, x0
    ret

# OP_THASH2_256: n=32, robust mode
# Encoding: opcode=0x5b, funct3=3, funct7=0x06 (per hash_pkg.sv)
thash2_256_hw_compute:
    .insn r 0x5b, 3, 0x06, x0, x0, x0
    ret

# THASH1_256_SIMPLE: n=32, simple mode
thash1_256_simple_hw_compute:
    li t0, 1
    .insn r 0x5b, 3, 0x05, x0, x0, t0
    ret

# THASH2_256_SIMPLE: n=32, simple mode
thash2_256_simple_hw_compute:
    li t0, 1
    .insn r 0x5b, 3, 0x06, x0, x0, t0
    ret

# PRF_ADDR_256: n=32
# Encoding: opcode=0x5b, funct3=3, funct7=0x08
prf_256_hw_compute:
    .insn r 0x5b, 3, 0x08, x0, x0, x0
    ret
