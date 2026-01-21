# kyber_ntt_S(int16_t r[256])
# a0: Base address of array r

.section .text
.global kyber_ntt_S

kyber_ntt_S:
    # Save callee-saved registers if needed (using t-registers here to avoid overhead)
    # t0: len
    # t1: start
    # t2: j
    # t3: k
    # t4: kyber_zetas pointer
    # t5: zeta
    # t6: j_limit (start + len)
    # a1: rj
    # a2: rlen
    # a3: t (butterfly temporary)
    # a4: address of r[j]
    # a5: address of r[j + len]

    li      t3, 1               # k = 1
    la      t4, kyber_zetas     # Load address of kyber_zetas array
    li      t0, 128             # len = 128

outer_loop:
    li      t1, 0               # start = 0
    li      s0, 256             # Loop bound for start

middle_loop:
    # zeta = kyber_zetas[k++]
    slli    t5, t3, 1           # k * 2 (offset for int16_t)
    add     t5, t4, t5          # &kyber_zetas[k]
    lh      t5, 0(t5)           # Load zeta (16-bit signed)
    addi    t3, t3, 1           # k++

    mv      t2, t1              # j = start
    add     t6, t1, t0          # j_limit = start + len

inner_loop:
    # Calculate addresses: r[j] and r[j + len]
    slli    a4, t2, 1           # j * 2
    add     a4, a0, a4          # &r[j]
    slli    a5, t0, 1           # len * 2
    add     a5, a4, a5          # &r[j + len]

    # Load coefficients
    lh      a1, 0(a4)           # rj = r[j]
    lh      a2, 0(a5)           # rlen = r[j + len]

    # Butterfly Operation
    mul     a3, t5, a2          # t = zeta * rlen (32-bit mul)
    
    # Custom hardware instruction for modular reduction
    .insn r 0x7b, 0x01, 0x0, a3, a3, x0

    sub     a2, a1, a3          # rlen = rj - t
    add     a1, a1, a3          # rj = rj + t

    # Store coefficients back
    sh      a1, 0(a4)           # r[j] = rj
    sh      a2, 0(a5)           # r[j + len] = rlen

    addi    t2, t2, 1           # j++
    blt     t2, t6, inner_loop  # if (j < start + len) goto inner_loop

    # Update start: start = j + len. 
    # Since j is currently (start + len), start becomes start + 2*len
    mv      t1, t2              # start = j
    add     t1, t1, t0          # start += len
    blt     t1, s0, middle_loop # if (start < 256) goto middle_loop

    srli    t0, t0, 1           # len >>= 1
    li      t6, 2
    bge     t0, t6, outer_loop  # if (len >= 2) goto outer_loop

    ret