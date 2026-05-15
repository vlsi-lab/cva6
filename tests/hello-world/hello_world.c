/*
**
** Copyright 2020 OpenHW Group
**
** Licensed under the Solderpad Hardware Licence, Version 2.0 (the "License");
** you may not use this file except in compliance with the License.
** You may obtain a copy of the License at
**
**     https://solderpad.org/licenses/
**
** Unless required by applicable law or agreed to in writing, software
** distributed under the License is distributed on an "AS IS" BASIS,
** WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
** See the License for the specific language governing permissions and
** limitations under the License.
**
*/

#include <stdint.h>
#include <stdio.h>
#include <inttypes.h>

#include "uart.h"
#include "encoding.h"

int main(int argc, char* arg[]) {

	printf("%d: Hello World !\n", 0);

	/* Cycle-count a small loop using cva6's encoding.h CSR helpers
	 * (replaces the X-HEEP CSR_WRITE/CSR_READ pattern). */
	clear_csr(mcountinhibit, 1);
	write_csr(mcycle, 0);

	int a = 0;
	for (int i = 0; i < 5; i++)
	{
		a += i;
	}

	uint32_t cycles = (uint32_t)read_csr(mcycle);

	print_uart("Number of clock cycles for hello-world loop: 0x");
	print_uart_int(cycles);
	print_uart("\n");

	printf("cycles = %" PRIu32 "\n", cycles);

	print_uart("Hi World! :)\n");
	return 0;
}
