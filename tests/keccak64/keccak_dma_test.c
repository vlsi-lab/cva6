// Keccak Accelerator IP - DMA job engine, Phase 0 sanity test
//
// Proves the new AXI-master plumbing (keccak_dma_ctrl + the third crossbar
// initiator port) in isolation from any sponge/absorb logic: fill a known
// buffer in memory, point the JOB_SRC_ADDR/JOB_SRC_LEN/JOBCTRL.GO descriptor
// at it, and check that the accelerator DMA-reads it into DATA[0..24]
// itself -- no CPU register-store loop involved on the input side.

#include "inc/uart.h"
#include "encoding.h"
#include "vrf_axi.h"

#define VRF_BASE_ADDR 0x50000000UL

int main()
{
	static uint64_t src_buf[25];
	uint64_t volatile *cryptoState =
	    (uint64_t volatile *)(VRF_BASE_ADDR + VRF_DATA_0_REG_OFFSET);
	uint64_t volatile *job_src_addr =
	    (uint64_t volatile *)(VRF_BASE_ADDR + VRF_JOB_SRC_ADDR_REG_OFFSET);
	uint64_t volatile *job_src_len =
	    (uint64_t volatile *)(VRF_BASE_ADDR + VRF_JOB_SRC_LEN_REG_OFFSET);
	uint64_t volatile *jobctrl =
	    (uint64_t volatile *)(VRF_BASE_ADDR + VRF_JOBCTRL_REG_OFFSET);
	int errors = 0;
	int cycles;

	printf("Keccak DMA job engine - Phase 0 (DMA read into DATA[])\n");

	for (int i = 0; i < 25; i++) {
		src_buf[i] = 0x0102030405060708ULL * (uint64_t)(i + 1);
	}

	// ensure the buffer writes above are visible to memory before the
	// accelerator's AXI master reads them
	__asm__ volatile ("fence" ::: "memory");

	clear_csr(mcountinhibit, 1);
	write_csr(mcycle, 0);

	*job_src_addr = (uint64_t)(uintptr_t)src_buf;
	*job_src_len  = 25 * 8;
	*jobctrl = (uint64_t)1 << VRF_JOBCTRL_GO_BIT;

	while (((*jobctrl) & ((uint64_t)1 << VRF_JOBCTRL_DONE_BIT)) == 0);

	cycles = read_csr(mcycle);

	// explicit zero write: genuinely clears GO/DONE rather than
	// preserving whatever was last read (see JOBCTRL protocol notes)
	*jobctrl = 0;

	printf("Number of clock cycles for DMA job (25 words): %d\n", cycles);

	for (int i = 0; i < 25; i++) {
		uint64_t got = cryptoState[i];
		if (got != src_buf[i]) {
			printf("!!! Mismatch at DATA[%d]: expected 0x%016llx, got 0x%016llx !!!\n",
			    i, src_buf[i], got);
			errors++;
		}
	}

	if (errors == 0)
		printf("Keccak DMA Phase 0 test terminated with no errors.\n");
	else
		printf("Keccak DMA Phase 0 test terminated with %d errors\n", errors);

	return 0;
}
