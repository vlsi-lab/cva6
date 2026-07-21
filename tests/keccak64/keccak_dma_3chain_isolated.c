// Isolated (single-case, nothing run before it) 3-internally-chained-
// permutation absorb test, to check whether the chain_bisect_test.c 3-chain
// failure is a genuine RTL defect independent of test-case ordering, or an
// artifact of running after the 1-chain/2-chain cases in the same process.

#include "inc/uart.h"
#include "encoding.h"
#include "keccak_axi.h"

#define KECCAK_BASE_ADDR 0x50000000UL

static uint64_t volatile *cryptoState =
    (uint64_t volatile *)(KECCAK_BASE_ADDR + KECCAK_DATA_0_REG_OFFSET);
static uint64_t volatile *job_src_addr =
    (uint64_t volatile *)(KECCAK_BASE_ADDR + KECCAK_JOB_SRC_ADDR_REG_OFFSET);
static uint64_t volatile *job_src_len =
    (uint64_t volatile *)(KECCAK_BASE_ADDR + KECCAK_JOB_SRC_LEN_REG_OFFSET);
static uint64_t volatile *jobctrl =
    (uint64_t volatile *)(KECCAK_BASE_ADDR + KECCAK_JOBCTRL_REG_OFFSET);
static uint64_t volatile *csreg =
    (uint64_t volatile *)(KECCAK_BASE_ADDR + KECCAK_CSREG_REG_OFFSET);

static void
run_job(const void *src, uint32_t len, int fresh, int flip, int dptr)
{
	__asm__ volatile ("fence" ::: "memory");
	*job_src_addr = (uint64_t)(uintptr_t)src;
	*job_src_len  = len;

	uint64_t ctrl = (uint64_t)1 << KECCAK_JOBCTRL_GO_BIT;
	if (fresh) ctrl |= (uint64_t)1 << KECCAK_JOBCTRL_FRESH_BIT;
	if (flip)  ctrl |= (uint64_t)1 << KECCAK_JOBCTRL_FLIP_BIT;
	ctrl |= ((uint64_t)(dptr & KECCAK_JOBCTRL_DPTR_MASK)) << KECCAK_JOBCTRL_DPTR_OFFSET;

	*jobctrl = ctrl;
	while (((*jobctrl) & ((uint64_t)1 << KECCAK_JOBCTRL_DONE_BIT)) == 0);
	*jobctrl = 0;
}

static void
permute_resident(void)
{
	*csreg |= (uint64_t)1 << KECCAK_CSREG_START_BIT;
	while (((*csreg) & ((uint64_t)1 << KECCAK_CSREG_DONE_BIT)) == 0);
	*csreg = 0;
}

static uint8_t pub[450];

static const uint8_t expected[16] = {
	0x53, 0x7f, 0xe2, 0x31, 0xb2, 0xa7, 0x40, 0xce,
	0x16, 0xce, 0x8d, 0x23, 0x08, 0xe7, 0x5a, 0xe0,
};

int
main(void)
{
	uint8_t got[16];
	int errors = 0;

	for (int i = 0; i < 450; i++) {
		pub[i] = (uint8_t)(i * 7 + 3);
	}

	printf("3-chain isolated test start\n");
	run_job(pub, 450, 1, 0, 0);
	printf("absorb done\n");
	run_job(0, 0, 0, 1, 450 % 136);
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
