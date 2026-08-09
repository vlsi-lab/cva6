#include <stdint.h>
#include "encoding.h"
#include "hal_cva6.h"

/* Throttled poll: small delay between successive STATUS reads, instead of
   hammering the register every cycle. */
static int do_op_throttled(uint32_t op_type, uint32_t robust, uint32_t n) {
    uint8_t seed[32]; uint8_t adrs[32]; uint8_t in1[32];
    for (int i = 0; i < 32; i++) { seed[i] = (uint8_t)i; adrs[i] = (uint8_t)(i+1); in1[i] = (uint8_t)(i+2); }
    ca_load_seed(seed, n);
    ca_load_adrs(adrs);
    ca_load_chain(in1, n);
    CHAIN_REG[CA_CTRL] = CA_CTRL_GO(op_type, robust, n, 1, 0);

    uint32_t polls = 0;
    while (!(CHAIN_REG[CA_STATUS] & 1u)) {
        for (volatile int d = 0; d < 1; d++) { }  /* throttle between reads */
        polls++;
        if (polls > 200u) return -1;
    }
    return 0;
}

int main(void) {
    clear_csr(mcountinhibit, 1);
    int fails = 0;
    for (int i = 0; i < 8; i++) {
        if (do_op_throttled(CA_OP_THASH1, i % 2, 16 + 8 * (i % 3 == 2)) < 0)
            fails |= (1 << i);
    }
    return fails == 0 ? 0x55 : (0x80 | fails);
}
