/****************************************************************************************
# Simple custom test:       trigger.c
# Author:                   Alessandra Dolmeta
# Description:              Test the trigger-peripheral.
/****************************************************************************************/


#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "trigger_auto.h"
#include "uart.h"


//**********************MAIN******************************************/
int main() {


    uint32_t volatile * trigger = (uint32_t*)TRIGGER_CTRL;
    uint32_t a,b,c;

    asm volatile ("": : : "memory");
    *trigger = 1 << TRIGGER_CTRL_START;
    asm volatile ("": : : "memory");
    *trigger = 1 << TRIGGER_CTRL_STOP;
    asm volatile ("": : : "memory");

    c = a +b;

    *trigger = 1 << TRIGGER_CTRL_START;
    asm volatile ("": : : "memory");
    *trigger = 1 << TRIGGER_CTRL_STOP;
    asm volatile ("": : : "memory");
    *trigger = 1 << TRIGGER_CTRL_START;
    asm volatile ("": : : "memory");
    *trigger = 1 << TRIGGER_CTRL_STOP;
    asm volatile ("": : : "memory");


    return 0;
}
