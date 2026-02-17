// Copyright OpenHW Group contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

#include "uart.h"
#include "spi.h"
#include "sd.h"
#include "gpt.h"

#define SECOND_CYCLES   CLOCK_FREQUENCY
#define WAIT_SECONDS    (10)

static inline uintptr_t get_cycle_count() {
    uintptr_t cycle;
    __asm__ volatile ("csrr %0, cycle" : "=r" (cycle));
    return cycle;
}

int update(uint8_t *dest)
{
    int i;
    uint32_t size = 0;

    print_uart("receiving boot image\r\nsize: ");
    for(i = 0; i < sizeof(uint32_t); i++) {
        while(!read_serial(&((uint8_t *) &size)[i]));
    }

    print_uart_int(size);
    print_uart("\r\nreceiving ");

    for(i = 0; i < size; i++) {
        while(!read_serial(&dest[i]));

        if(i % (size >> 4) == 0) {
            print_uart(".");
        }
    }

    print_uart(" done!\r\n");
    return 0;
}

int main()
{
    int i, ret = 0;
    uint8_t uart_res = 0;
    uintptr_t start;


    //#ifndef PLAT_AGILEX
    init_uart(CLOCK_FREQUENCY, UART_BITRATE); //not needed in intel setup as UART IP is already configured via HW
    //#endif 
    print_uart("Ti prego funziona plz :( \r\n");

    // See if we should enter update mode
    print_uart("Hit any key to enter update mode ");
    for(i = 0; i < WAIT_SECONDS && !ret; i++) {
        print_uart(".");
        start = get_cycle_count();
        while(get_cycle_count() - start < SECOND_CYCLES) {
            ret = read_serial(&uart_res);
            if(ret) {
                break;
            }
        }
    }

    int res = 0;
    if(ret) {

        print_uart("\n\rUpdate mode!");
        // Assuming a maximum size of 64KiB for the new image
        uint32_t size = 65536;

        print_uart("\r\nreceiving ");
        uint8_t *dest = (uint8_t *)0x80000000UL;
        for(i = 0; i < size; i++) {
            while(!read_serial(&dest[i]));
        }

        print_uart("\n\rUpdate done!");
        res = 0;
    } else {
        print_uart("\n\rBooting...");
    }

    if (res == 0)
    {
        print_uart("\r\nJumping to 0x80000000");
        __asm__ volatile(
            "li s0, 0x80000000;"
            "jr s0");
    }

    while (1)
    {
        // do nothing
    }
}

void handle_trap(void)
{
    // print_uart("trap\r\n");
}
