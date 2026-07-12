# Ascon Accelerator IP - Tightly
# RV64 Ascon permutation (P12) using the accelerator custom instructions
# Author: Federico Runco

.section .rodata
.align 3
ascon_rc:
.quad 0xf0
.quad 0xe1
.quad 0xd2
.quad 0xc3
.quad 0xb4
.quad 0xa5
.quad 0x96
.quad 0x87
.quad 0x78
.quad 0x69
.quad 0x5a
.quad 0x4b

.text

.macro xor3 dest, a, b, c
    .insn r4 CUSTOM_1, 0x0, 0x02, \dest, \a, \b, \c
.endm

.macro xandn dest, a, b, c
    .insn r4 CUSTOM_1, 0x01, 0x02, \dest, \a, \b, \c
.endm

.macro drorx rd, rs1, r1, r2
    .insn i CUSTOM_0, 0x0, \rd, \rs1, (((((\r1 & 0x3f) << 6) | (\r2 & 0x3f))) - (((\r1 >> 5) & 0x1) << 12))
.endm

.globl P12
.align 2
P12:
    # Load state
    ld  t0, 0*8(a0)
    ld  t1, 1*8(a0)
    ld  t2, 2*8(a0)
    ld  t3, 3*8(a0)
    ld  t4, 4*8(a0)

    la  a6, ascon_rc         # round-constant pointer
    li  a7, 12               # 12 rounds

.Lround:
    # round constant + column XORs
    ld   t5, 0(a6)           # rc[round]
    xor3 t2, t2, t5, t1      # s02 ^= rc[round] ; s02 ^= s01
    xor  t0, t0, t4          # s00 ^= s04
    xor  t4, t4, t3          # s04 ^= s03

    # substitution layer (Ascon S-box): t00..t04 -> a1..a5
    xandn a1, t0, t1, t2     # t00 = s00 ^ (~s01 & s02)
    xandn a2, t1, t2, t3     # t01 = s01 ^ (~s02 & s03)
    xandn a3, t2, t3, t4     # t02 = s02 ^ (~s03 & s04)
    xandn a4, t3, t4, t0     # t03 = s03 ^ (~s04 & s00)
    xandn a5, t4, t0, t1     # t04 = s04 ^ (~s00 & s01)

    xor  a2, a2, a1          # t01 ^= t00
    xor  a1, a1, a5          # t00 ^= t04
    xor  a4, a4, a3          # t03 ^= t02
    not  a3, a3              # t02 = ~t02

    # linear diffusion layer: new s00..s04 -> t0..t4
    drorx t0, a1, 19, 28     # s00 = t00 ^ ROR(t00,19) ^ ROR(t00,28)
    drorx t1, a2, 61, 39     # s01 = t01 ^ ROR(t01,61) ^ ROR(t01,39)
    drorx t2, a3, 1,  6      # s02 = t02 ^ ROR(t02,1)  ^ ROR(t02,6)
    drorx t3, a4, 10, 17     # s03 = t03 ^ ROR(t03,10) ^ ROR(t03,17)
    drorx t4, a5, 7,  41     # s04 = t04 ^ ROR(t04,7)  ^ ROR(t04,41)

    addi a6, a6, 8
    addi a7, a7, -1
    bnez a7, .Lround

    # Store state
    sd  t0, 0*8(a0)
    sd  t1, 1*8(a0)
    sd  t2, 2*8(a0)
    sd  t3, 3*8(a0)
    sd  t4, 4*8(a0)
    ret
