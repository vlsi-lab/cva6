// Keccak Accelerator IP - DMA job engine, Phase 1 correctness test
//
// Exercises the real absorb engine (block chaining, hardware XOR-absorb,
// pad10*1 padding, and dptr continuation across separate job calls) and
// checks results against an independently computed Keccak-f1600/SHAKE256
// reference (Python, validated against hashlib before use). No full HAWK
// KAT run needed to catch register-map, addressing, or sponge-math bugs
// here -- this is the fast register-level gate that must pass first.

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

static int errors = 0;

static uint8_t
msg_byte(int i)
{
	return (uint8_t)(i * 7 + 3);
}

static uint8_t
msg_byte_b(int i)
{
	return (uint8_t)(i * 13 + 201);
}

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
check_word(const char *test, int idx, uint64_t got, uint64_t want)
{
	if (got != want) {
		printf("!!! %s mismatch DATA[%d]: expected 0x%016llx, got 0x%016llx !!!\n",
		    test, idx, want, got);
		errors++;
	}
}

static void
read_state_bytes(uint8_t *out)
{
	for (int w = 0; w < 25; w++) {
		uint64_t v = cryptoState[w];
		for (int b = 0; b < 8; b++) {
			out[w * 8 + b] = (uint8_t)(v >> (b * 8));
		}
	}
}

int
main()
{
	static uint8_t msg[256];
	static uint8_t got_bytes[200];

	for (int i = 0; i < 256; i++) {
		msg[i] = msg_byte(i);
	}

	printf("Keccak DMA job engine - Phase 1 (absorb/chain/flip)\n");

	// Test A: partial absorb (41 of 136 bytes), no permute expected --
	// DATA[] should hold the message bytes XORed into the zeroed state,
	// byte for byte, nothing else touched.
	run_job(msg, 41, 1, 0, 0);
	read_state_bytes(got_bytes);
	for (int i = 0; i < 41; i++) {
		if (got_bytes[i] != msg[i]) {
			printf("!!! Test A byte %d mismatch: expected 0x%02x, got 0x%02x !!!\n",
			    i, msg[i], got_bytes[i]);
			errors++;
		}
	}
	for (int i = 41; i < 200; i++) {
		if (got_bytes[i] != 0) {
			printf("!!! Test A byte %d should be zero, got 0x%02x !!!\n", i, got_bytes[i]);
			errors++;
		}
	}
	printf("Test A (partial absorb, no permute) done\n");

	// Test B: exactly one full rate block (136 bytes) in a single job --
	// must trigger exactly one chained permutation.
	static const uint64_t D_expected_B[25] = {
		0x72F216F8D9266CE3ULL, 0xA7285B63639EB320ULL, 0xFB6D1D4361D4133EULL,
		0x50CAD805C2D3E975ULL, 0x2B961CB34DDC87B5ULL, 0xBF9164CBD04AF04EULL,
		0x60D31F933CDD6DC0ULL, 0xAC8679CC60946FAAULL, 0xD18870F74C61F015ULL,
		0x62889ED947BE74C7ULL, 0xA8152477E192463FULL, 0x4E05B3D653EA0CCBULL,
		0x5D8262CD938DBFB6ULL, 0xBCA1098A7E72D1A1ULL, 0xEB3100A3AFDAAC7BULL,
		0x2D9FDCFB33B55E9AULL, 0x61E75D6A41111AEDULL, 0xFDEE27A1CE22F952ULL,
		0xC6D07F2E1B55C782ULL, 0xB3CF175AA9766A95ULL, 0xEF0DE584FEACACA8ULL,
		0x5507E69EBA171890ULL, 0xA28DC5EECE8B18E7ULL, 0xA2D95388E0235989ULL,
		0x46D9809BBCB4C85EULL,
	};
	run_job(msg, 136, 1, 0, 0);
	for (int i = 0; i < 25; i++) {
		check_word("Test B", i, cryptoState[i], D_expected_B[i]);
	}
	printf("Test B (full-block absorb, chained permute) done\n");

	// Test C: partial absorb (41 bytes) plus FLIP in the same job --
	// pad10*1 applied at byte 41 and byte 135, no permutation forced.
	run_job(msg, 41, 1, 1, 0);
	read_state_bytes(got_bytes);
	for (int i = 0; i < 41; i++) {
		if (got_bytes[i] != msg[i]) {
			printf("!!! Test C byte %d mismatch: expected 0x%02x, got 0x%02x !!!\n",
			    i, msg[i], got_bytes[i]);
			errors++;
		}
	}
	if (got_bytes[41] != 0x1F) {
		printf("!!! Test C pad byte 41: expected 0x1f, got 0x%02x !!!\n", got_bytes[41]);
		errors++;
	}
	if (got_bytes[135] != 0x80) {
		printf("!!! Test C pad byte 135: expected 0x80, got 0x%02x !!!\n", got_bytes[135]);
		errors++;
	}
	for (int i = 42; i < 135; i++) {
		if (got_bytes[i] != 0) {
			printf("!!! Test C byte %d should be zero, got 0x%02x !!!\n", i, got_bytes[i]);
			errors++;
		}
	}
	printf("Test C (partial absorb + flip padding) done\n");

	// Test I: same result as Test C, but the absorb and the flip are two
	// SEPARATE jobs (as shake_inject() followed later by a standalone
	// shake_flip() job actually issues), instead of one combined job.
	// The flip-only job has SRC_LEN=0 and relies on JOBCTRL.DPTR alone
	// (no absorb precedes it in the same job) to know where to place the
	// padding -- this is the one code path Test C's combined job never
	// actually exercises (there, blk_off reaches 41 via the absorb
	// itself, not via job_dptr_i read directly at FLIP_BYTE0 time).
	run_job(msg, 41, 1, 0, 0);
	run_job(msg, 0, 0, 1, 41);
	read_state_bytes(got_bytes);
	for (int i = 0; i < 41; i++) {
		if (got_bytes[i] != msg[i]) {
			printf("!!! Test I byte %d mismatch: expected 0x%02x, got 0x%02x !!!\n",
			    i, msg[i], got_bytes[i]);
			errors++;
		}
	}
	if (got_bytes[41] != 0x1F) {
		printf("!!! Test I pad byte 41: expected 0x1f, got 0x%02x !!!\n", got_bytes[41]);
		errors++;
	}
	if (got_bytes[135] != 0x80) {
		printf("!!! Test I pad byte 135: expected 0x80, got 0x%02x !!!\n", got_bytes[135]);
		errors++;
	}
	for (int i = 42; i < 135; i++) {
		if (got_bytes[i] != 0) {
			printf("!!! Test I byte %d should be zero, got 0x%02x !!!\n", i, got_bytes[i]);
			errors++;
		}
	}
	printf("Test I (separate flip-only job, non-zero dptr) done\n");

	// Test D: 200 bytes absorbed in a single job -- one full block
	// chained through the permutation, then the trailing 64 bytes
	// XORed onto the resulting state.
	static const uint64_t D_expected_D[25] = {
		0x9E17C82F09EFAE58ULL, 0x83354D6C6B9F49D3ULL, 0xA738530421ED2115ULL,
		0xC4475E7ABAA28316ULL, 0xE753A204FD75252EULL, 0xBB6C922438AB2A9DULL,
		0x5CE631B41CC47FCBULL, 0xD8EB1F9338C525E9ULL, 0xD18870F74C61F015ULL,
		0x62889ED947BE74C7ULL, 0xA8152477E192463FULL, 0x4E05B3D653EA0CCBULL,
		0x5D8262CD938DBFB6ULL, 0xBCA1098A7E72D1A1ULL, 0xEB3100A3AFDAAC7BULL,
		0x2D9FDCFB33B55E9AULL, 0x61E75D6A41111AEDULL, 0xFDEE27A1CE22F952ULL,
		0xC6D07F2E1B55C782ULL, 0xB3CF175AA9766A95ULL, 0xEF0DE584FEACACA8ULL,
		0x5507E69EBA171890ULL, 0xA28DC5EECE8B18E7ULL, 0xA2D95388E0235989ULL,
		0x46D9809BBCB4C85EULL,
	};
	run_job(msg, 200, 1, 0, 0);
	for (int i = 0; i < 25; i++) {
		check_word("Test D", i, cryptoState[i], D_expected_D[i]);
	}
	printf("Test D (multi-block chained absorb) done\n");

	static const uint64_t D_expected_H[25] = {
		0x9E17C82F09EFAE58ULL, 0x83354D6C6B9F49D3ULL, 0xA738530421ED2115ULL,
		0xC4475E7ABAA28316ULL, 0xE753A204FD75252EULL, 0xBB6C922438AB2A9DULL,
		0x5CE631B41CC47FCBULL, 0xD8EB1F9338C525E9ULL, 0x7D2DEE60DCE8726EULL,
		0x865548168F7FCE74ULL, 0xB4002A70E16BB4D4ULL, 0x1A48F5E96BDB26E8ULL,
		0xD1071CBAE3E4DDEDULL, 0x781CBF25D6D34B32ULL, 0xEB3100A3AFDA7EB0ULL,
		0x2D9FDCFB33B55E9AULL, 0x61E75D6A41111AEDULL, 0xFDEE27A1CE22F952ULL,
		0xC6D07F2E1B55C782ULL, 0xB3CF175AA9766A95ULL, 0xEF0DE584FEACACA8ULL,
		0x5507E69EBA171890ULL, 0xA28DC5EECE8B18E7ULL, 0xA2D95388E0235989ULL,
		0x46D9809BBCB4C85EULL,
	};

	// Test E: the same 136-byte message as Test B, but split across two
	// separate jobs with dptr continuation (fresh 100 bytes, then a
	// resumed 36-byte job at dptr=100) -- must reach the identical final
	// state as the one-shot Test B absorb. This is exactly the pattern
	// HAWK's real shake_inject call sequence exercises.
	run_job(msg, 100, 1, 0, 0);
	run_job(msg + 100, 36, 0, 0, 100);
	for (int i = 0; i < 25; i++) {
		check_word("Test E", i, cryptoState[i], D_expected_B[i]);
	}
	printf("Test E (dptr continuation across two jobs) done\n");

	// Test F: same 200-byte message as Test D, but split as 41 then 159
	// bytes across two jobs -- the second job starts at a non-zero dptr
	// (41) AND spans a block boundary within itself (crosses at byte 95
	// of the job, i.e. absorbed byte 136 overall). Must match Test D's
	// expected state exactly.
	run_job(msg, 41, 1, 0, 0);
	run_job(msg + 41, 159, 0, 0, 41);
	for (int i = 0; i < 25; i++) {
		check_word("Test F", i, cryptoState[i], D_expected_D[i]);
	}
	printf("Test F (non-zero-dptr multi-block-spanning absorb) done\n");

	// Test G: same as Test F, but with a simulated context-switch
	// eviction+restore (legacy DATA[] MMIO read-out then write-back, as
	// keccak_hw_prepare_for_absorb() does when a different context was
	// resident in between) inserted after the first job and before the
	// continuing job -- isolates whether the save/restore round trip
	// itself corrupts the resident state.
	{
		uint64_t saved[25];

		run_job(msg, 41, 1, 0, 0);
		for (int i = 0; i < 25; i++) {
			saved[i] = cryptoState[i];
		}
		for (int i = 0; i < 25; i++) {
			cryptoState[i] = saved[i];
		}
		run_job(msg + 41, 159, 0, 0, 41);
		for (int i = 0; i < 25; i++) {
			check_word("Test G", i, cryptoState[i], D_expected_D[i]);
		}
	}
	printf("Test G (multi-block absorb after simulated evict/restore) done\n");

	// Test H: raw job calls reproducing the exact A1/B1/A2/B2/A3
	// interleaving sequence used by the software-level interleave test
	// (tests/hawk-256-keccak/keccak_interleave_test.c), including real
	// intervening FRESH jobs for "B" that fully overwrite DATA[], with
	// explicit evict/restore round trips in between -- isolates whether
	// this exact sequence is correct at the register level, independent
	// of the shake_context driver.
	{
		static uint8_t msgB[90];
		uint64_t savedA[25], savedB[25];

		for (int i = 0; i < 90; i++) {
			msgB[i] = msg_byte_b(i);
		}

		run_job(msg, 41, 1, 0, 0);                 // A1: fresh, dptr 0->41
		for (int i = 0; i < 25; i++) savedA[i] = cryptoState[i];

		run_job(msgB, 30, 1, 0, 0);                // B1: fresh, dptr 0->30
		for (int i = 0; i < 25; i++) savedB[i] = cryptoState[i];
		for (int i = 0; i < 25; i++) cryptoState[i] = savedA[i];

		run_job(msg + 41, 159, 0, 0, 41);           // A2: dptr 41->64
		for (int i = 0; i < 25; i++) savedA[i] = cryptoState[i];
		for (int i = 0; i < 25; i++) cryptoState[i] = savedB[i];

		run_job(msgB + 30, 60, 0, 0, 30);           // B2: dptr 30->90
		for (int i = 0; i < 25; i++) savedB[i] = cryptoState[i];
		for (int i = 0; i < 25; i++) cryptoState[i] = savedA[i];

		run_job(msg + 200, 50, 0, 0, 64);           // A3: dptr 64->114

		for (int i = 0; i < 25; i++) {
			check_word("Test H", i, cryptoState[i], D_expected_H[i]);
		}
	}
	printf("Test H (raw-job A/B interleave reproduction) done\n");

	if (errors == 0)
		printf("Keccak DMA Phase 1 test terminated with no errors.\n");
	else
		printf("Keccak DMA Phase 1 test terminated with %d errors\n", errors);

	return 0;
}
