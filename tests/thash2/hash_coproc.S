#include "../inc/hash_coproc.S"

.section .text
.global thash2_hw_compute
.align 4

# void thash2_hw_compute(void);
#   - Triggers OP_THASH2 with simple-mode flag = 0 (robust).
thash2_hw_compute:
    .insn r 0x5b, 3, 0x01, x0, x0, x0
    ret
