// Measures the cycle cost of a single CSREG-triggered permutation call in
// isolation: 25 stores (upload) + CSREG.START + poll + 25 loads (readback),
// to separate "fixed per-call overhead" from "24-round compute time" and
// decide where further optimization effort is best spent.

#include "inc/uart.h"
#include "encoding.h"
#include "vrf_axi.h"

#define VRF_BASE_ADDR 0x50000000UL

int
main(void)
{
	uint64_t volatile *cryptoState =
	    (uint64_t volatile *)(VRF_BASE_ADDR + VRF_DATA_0_REG_OFFSET);
	uint64_t volatile *csreg =
	    (uint64_t volatile *)(VRF_BASE_ADDR + VRF_CSREG_REG_OFFSET);
	static uint64_t A[25];
	int cycles_full, cycles_upload, cycles_poll, cycles_readback;
	int i;

	for (i = 0; i < 25; i++) A[i] = 0x0102030405060708ULL * (uint64_t)(i + 1);

	/* full round trip: upload + start + poll + readback */
	clear_csr(mcountinhibit, 1);
	write_csr(mcycle, 0);
	for (i = 0; i < 25; i++) cryptoState[i] = A[i];
	*csreg |= (uint64_t)1 << VRF_CSREG_START_BIT;
	while (((*csreg) & ((uint64_t)1 << VRF_CSREG_DONE_BIT)) == 0);
	for (i = 0; i < 25; i++) A[i] = cryptoState[i];
	*csreg = 0;
	cycles_full = read_csr(mcycle);

	/* upload only (25 stores) */
	write_csr(mcycle, 0);
	for (i = 0; i < 25; i++) cryptoState[i] = A[i];
	cycles_upload = read_csr(mcycle);

	/* start + poll only (compute + handshake, no data movement) */
	write_csr(mcycle, 0);
	*csreg |= (uint64_t)1 << VRF_CSREG_START_BIT;
	while (((*csreg) & ((uint64_t)1 << VRF_CSREG_DONE_BIT)) == 0);
	cycles_poll = read_csr(mcycle);
	*csreg = 0;

	/* readback only (25 loads) */
	write_csr(mcycle, 0);
	for (i = 0; i < 25; i++) A[i] = cryptoState[i];
	cycles_readback = read_csr(mcycle);

	printf("Single permutation call cost breakdown:\n");
	printf("  full round trip (upload+start+poll+readback): %d cycles\n", cycles_full);
	printf("  upload (25 stores):                            %d cycles\n", cycles_upload);
	printf("  start+poll (compute+handshake):                 %d cycles\n", cycles_poll);
	printf("  readback (25 loads):                            %d cycles\n", cycles_readback);
	return 0;
}
