/****************************************************************************************
 * Simple custom test: trigger.c
 *
 * Exercises the AXI-mapped trigger_ip peripheral mapped at TRIGGER0_BASE_ADDR
 * (0x4100_0000). The test:
 *   1. Prints a banner on the UART.
 *   2. Reads back the STATUS register to confirm the slave responds.
 *   3. Pulses the trigger output a few times by writing START / STOP
 *      bits of the CTRL register, with compiler memory barriers between
 *      writes so they cannot be reordered.
 *   4. Reads back the GPIO_O register and prints it.
 *
 * On the testharness this drives the `trigger_gpio` wire instantiated next
 * to `i_trigger`; on the CW305 FPGA build it drives the `trigger_gpio_o`
 * pin (PACKAGE_PIN T14).
 ****************************************************************************************/

#include <stdint.h>
#include <stdio.h>

#include "trigger_auto.h"
#include "uart.h"

static inline void mem_barrier(void) {
    __asm__ volatile("" ::: "memory");
}

int main(void) {
    volatile uint32_t * const trigger_ctrl   = (uint32_t *)TRIGGER_CTRL;
    volatile uint32_t * const trigger_status = (uint32_t *)TRIGGER_STATUS;
    volatile uint32_t * const trigger_gpio   = (uint32_t *)TRIGGER_GPIO_O;

    printf("trigger_ip simulation test\n");

    uint32_t status_before = *trigger_status;
    printf("STATUS before = 0x%08x\n", (unsigned)status_before);

    /* Pulse the trigger a few times. */
    for (int i = 0; i < 3; i++) {
        mem_barrier();
        *trigger_ctrl = (1u << TRIGGER_CTRL_START);
        mem_barrier();
        *trigger_ctrl = (1u << TRIGGER_CTRL_STOP);
        mem_barrier();
    }

    uint32_t gpio_val      = *trigger_gpio;
    uint32_t status_after  = *trigger_status;
    printf("GPIO_O after  = 0x%08x\n", (unsigned)gpio_val);
    printf("STATUS after  = 0x%08x\n", (unsigned)status_after);

    printf("trigger_ip test done\n");
    return 0;
}
