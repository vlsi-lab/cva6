// Minimal single-case repro of the Keccak DMA multi-chain absorb bug, for
// waveform tracing: absorbs exactly 272 bytes (2 full 136-byte rate
// blocks, 2 internally-chained permutations, no CPU intervention between
// them), flips, permutes once more, and checks the result. Kept as small
// as possible (no 1-chain/3-chain control cases) to keep the VCD trace
// short.

#include "inc/uart.h"
#include "encoding.h"
#include "vrf_axi.h"

#define VRF_BASE_ADDR 0x50000000UL

static uint64_t volatile *cryptoState =
    (uint64_t volatile *)(VRF_BASE_ADDR + VRF_DATA_0_REG_OFFSET);
static uint64_t volatile *job_src_addr =
    (uint64_t volatile *)(VRF_BASE_ADDR + VRF_JOB_SRC_ADDR_REG_OFFSET);
static uint64_t volatile *job_src_len =
    (uint64_t volatile *)(VRF_BASE_ADDR + VRF_JOB_SRC_LEN_REG_OFFSET);
static uint64_t volatile *jobctrl =
    (uint64_t volatile *)(VRF_BASE_ADDR + VRF_JOBCTRL_REG_OFFSET);
static uint64_t volatile *csreg =
    (uint64_t volatile *)(VRF_BASE_ADDR + VRF_CSREG_REG_OFFSET);

static void
run_job(const void *src, uint32_t len, int fresh, int flip, int dptr)
{
	__asm__ volatile ("fence" ::: "memory");
	*job_src_addr = (uint64_t)(uintptr_t)src;
	*job_src_len  = len;

	uint64_t ctrl = (uint64_t)1 << VRF_JOBCTRL_GO_BIT;
	if (fresh) ctrl |= (uint64_t)1 << VRF_JOBCTRL_FRESH_BIT;
	if (flip)  ctrl |= (uint64_t)1 << VRF_JOBCTRL_FLIP_BIT;
	ctrl |= ((uint64_t)(dptr & VRF_JOBCTRL_DPTR_MASK)) << VRF_JOBCTRL_DPTR_OFFSET;

	*jobctrl = ctrl;
	while (((*jobctrl) & ((uint64_t)1 << VRF_JOBCTRL_DONE_BIT)) == 0);
	*jobctrl = 0;
}

static void
permute_resident(void)
{
	*csreg |= (uint64_t)1 << VRF_CSREG_START_BIT;
	while (((*csreg) & ((uint64_t)1 << VRF_CSREG_DONE_BIT)) == 0);
	*csreg = 0;
}

static uint8_t msg[272];

static const uint8_t expected[16] = {
	0xb1, 0xe5, 0x73, 0xab, 0x38, 0x32, 0xed, 0xec,
	0x07, 0xba, 0x86, 0x7c, 0xa1, 0x7d, 0x03, 0xcd,
};

int
main(void)
{
	uint8_t got[16];
	int errors = 0;

	for (int i = 0; i < 272; i++) {
		msg[i] = (uint8_t)(i * 7 + 3);
	}

	printf("2-chain trace repro start\n");
	run_job(msg, 272, 1, 0, 0);
	printf("absorb done\n");
	run_job(0, 0, 0, 1, 0);
	printf("flip done\n");
	permute_resident();
	printf("permute done\n");

	for (int i = 0; i < 2; i++) {
		uint64_t v = cryptoState[i];
		for (int b = 0; b < 8; b++) got[i * 8 + b] = (uint8_t)(v >> (b * 8));
	}
	for (int i = 0; i < 16; i++) {
		if (got[i] != expected[i]) errors++;
	}
	printf("errors=%d\n", errors);
	return 0;
}
