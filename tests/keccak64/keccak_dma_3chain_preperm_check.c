// Reads back the raw DATA[] state after a 3-internally-chained-permutation
// absorb job plus flip padding, WITHOUT going through CSREG at all, to
// isolate whether the absorb/flip result itself is correct for 3 chains
// (independent of any CSREG-triggered final permute).

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

static uint8_t pub[450];

int
main(void)
{
	for (int i = 0; i < 450; i++) {
		pub[i] = (uint8_t)(i * 7 + 3);
	}

	printf("3-chain pre-permute state dump\n");
	run_job(pub, 450, 1, 0, 0);
	printf("absorb done\n");
	run_job(0, 0, 0, 1, 450 % 136);
	printf("flip done\n");

	for (int i = 0; i < 25; i++) {
		printf("word[%d]=%016llx\n", i, (unsigned long long)cryptoState[i]);
	}
	return 0;
}
