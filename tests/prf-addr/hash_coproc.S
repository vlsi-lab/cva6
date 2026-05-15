#include "../inc/hash_coproc.S"

.section .text
.global prf_addr_hw_compute
.align 4

# void prf_addr_hw_compute(void);
#   - Triggers OP_PRF_ADDR (SPHINCS+ PRF over pub_seed || addr).
prf_addr_hw_compute:
    .insn r 0x5b, 3, 0x02, x0, x0, x0
    ret
