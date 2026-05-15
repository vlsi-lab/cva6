#include "../inc/hash_coproc.S"

.section .text
.global thash1_hw_compute
.align 4

# void thash1_hw_compute(void);
#   - Triggers OP_THASH1 with simple-mode flag = 0 (robust).
#   - The HW IP holds issue_ready low until the SPHINCS+ thash1 sequence
#     completes, so no NOP padding is needed.
thash1_hw_compute:
    .insn r 0x5b, 3, 0x00, x0, x0, x0
    ret
