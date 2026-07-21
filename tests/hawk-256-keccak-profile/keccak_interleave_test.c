/*
 * Software-level interleaved-context correctness test for the Phase 1
 * DMA absorb driver (shake_init/shake_inject/shake_flip/shake_extract in
 * sha3.c). This is the exact scenario that broke both earlier
 * hardware-residency attempts: two independent SHAKE256 contexts whose
 * shake_inject/shake_extract calls are interleaved, forcing the
 * accelerator's single resident-state slot to be evicted and restored
 * repeatedly. Results are checked against SHAKE256 digests computed
 * independently via Python's hashlib.
 *
 * This links only sha3.c (plus bare-metal startup) -- no other HAWK
 * source files -- since shake_init/shake_inject/shake_flip/shake_extract
 * are fully self-contained. Uses print_uart()/print_uart_dec() rather
 * than printf(), matching this directory's own main.c ("replaces printf
 * on CVA6").
 */

#include <stddef.h>
#include <stdint.h>
#include <string.h>

#include "uart.h"
#include "encoding.h"
#include "sha3.h"

static uint8_t
msg_byte_a(int i)
{
	return (uint8_t)(i * 7 + 3);
}

static uint8_t
msg_byte_b(int i)
{
	return (uint8_t)(i * 13 + 201);
}

static const uint8_t expected_A[96] = {
	0x1a, 0x64, 0x76, 0xa2, 0xdc, 0x78, 0x2d, 0x96, 0x19, 0x9e, 0x25, 0x03,
	0x36, 0xe6, 0xeb, 0x48, 0x73, 0xd8, 0x6e, 0xae, 0x21, 0xb7, 0xa9, 0xb2,
	0x93, 0x28, 0xfb, 0x04, 0x21, 0xc6, 0xf8, 0x49, 0xd0, 0x55, 0x91, 0x04,
	0xae, 0x18, 0xe3, 0xa7, 0x13, 0x9b, 0x5a, 0x21, 0x53, 0xe3, 0x1d, 0x92,
	0x8e, 0xa6, 0xe3, 0xa2, 0x48, 0x9d, 0xee, 0x64, 0x55, 0xcb, 0x9e, 0x20,
	0x3c, 0x3e, 0x49, 0x93, 0x32, 0xbf, 0xfa, 0xc8, 0x1e, 0xad, 0x01, 0xa5,
	0x21, 0x96, 0x1b, 0xeb, 0x52, 0x5a, 0xc3, 0x9f, 0x14, 0xe6, 0x2a, 0x66,
	0xbc, 0xfa, 0xd0, 0x6b, 0x74, 0x13, 0x29, 0xcc, 0x6c, 0x49, 0xd4, 0x93,
};

static const uint8_t expected_B[64] = {
	0x31, 0x44, 0x01, 0xe4, 0xda, 0xd4, 0xc6, 0xdf, 0x49, 0xa7, 0x8c, 0xb6,
	0x48, 0x63, 0x6f, 0x30, 0x9f, 0x37, 0xe3, 0x61, 0x43, 0xf0, 0x1d, 0x3e,
	0xa8, 0x0c, 0x0e, 0xea, 0xaa, 0x00, 0xc8, 0x78, 0xc5, 0x84, 0x90, 0x76,
	0x99, 0x7c, 0x71, 0xe1, 0x77, 0x1b, 0x35, 0x30, 0x39, 0xb0, 0x9e, 0xf9,
	0xdd, 0xf5, 0xdb, 0x46, 0xb8, 0xf5, 0x81, 0x84, 0xd0, 0x44, 0xeb, 0x8b,
	0xa2, 0x6b, 0xb6, 0xf5,
};

static void
report_mismatch(const char *ctx, int i, uint8_t want, uint8_t got)
{
	print_uart("!!! context ");
	print_uart(ctx);
	print_uart(" byte ");
	print_uart_dec(i);
	print_uart(" mismatch: expected 0x");
	print_uart_byte(want);
	print_uart(", got 0x");
	print_uart_byte(got);
	print_uart(" !!!\n");
}

static const uint8_t expected_stack2[32] = {
	0x36, 0x33, 0xee, 0x42, 0x69, 0x08, 0x60, 0x85, 0x91, 0x91, 0x53, 0x16,
	0x79, 0x1c, 0xa9, 0xdb, 0x03, 0x93, 0xa4, 0xf7, 0xc0, 0x9f, 0xd4, 0xa8,
	0x02, 0x74, 0x40, 0x25, 0xf5, 0xa7, 0x9b, 0x38,
};

/*
 * hw_owner is a raw pointer; if pointer identity alone were trusted, a
 * *different* logical shake_context landing at the same (reused) stack
 * address as a stale hw_owner would be misread as "already resident",
 * silently absorbing new input on top of an unrelated context's leftover
 * hardware state. This calls two separate functions, each with its own
 * local shake_context, back to back -- a pattern real compilers commonly
 * lay out at the same stack offset -- to catch that class of bug.
 */
static void __attribute__((noinline))
stack_use_1(void)
{
	shake_context sc;
	uint8_t out[16];

	shake_init(&sc, 256);
	shake_inject(&sc, "unrelated context 1 payload", 28);
	shake_flip(&sc);
	shake_extract(&sc, out, sizeof out);
	(void)out;
}

static uint8_t out_stack2[32];

static void __attribute__((noinline))
stack_use_2(void)
{
	static uint8_t msg2[60];
	shake_context sc;

	for (int i = 0; i < 60; i++) {
		msg2[i] = (uint8_t)(i * 17 + 5);
	}

	shake_init(&sc, 256);
	shake_inject(&sc, msg2, sizeof msg2);
	shake_flip(&sc);
	shake_extract(&sc, out_stack2, sizeof out_stack2);
}

int
main(void)
{
	static uint8_t msgA[250], msgB[90];
	static uint8_t outA[96], outB[64];
	shake_context scA, scB;
	int errors = 0;

	for (int i = 0; i < 250; i++) msgA[i] = msg_byte_a(i);
	for (int i = 0; i < 90; i++)  msgB[i] = msg_byte_b(i);

	print_uart("Keccak DMA driver - Phase 1 interleaved-context test\n");

	shake_init(&scA, 256);
	shake_init(&scB, 256);
	print_uart("init done\n");

	/*
	 * Interleave absorb calls with odd, non-block-aligned chunk sizes,
	 * bouncing the accelerator's single resident-state slot between
	 * scA and scB on every call -- this is what breaks a per-context
	 * (rather than global-owner) residency assumption.
	 */
	shake_inject(&scA, msgA,       41);
	print_uart("inject A1 done\n");
	shake_inject(&scB, msgB,       30);
	print_uart("inject B1 done\n");
	shake_inject(&scA, msgA + 41,  159);
	print_uart("inject A2 done\n");
	shake_inject(&scB, msgB + 30,  60);
	print_uart("inject B2 done\n");
	shake_inject(&scA, msgA + 200, 50);
	print_uart("inject A3 done\n");

	shake_flip(&scA);
	print_uart("flip A done\n");
	shake_flip(&scB);
	print_uart("flip B done\n");

	shake_extract(&scA, outA,      64);
	print_uart("extract A1 done\n");
	shake_extract(&scB, outB,      32);
	print_uart("extract B1 done\n");
	shake_extract(&scA, outA + 64, 32);
	print_uart("extract A2 done\n");
	shake_extract(&scB, outB + 32, 32);
	print_uart("extract B2 done\n");

	for (int i = 0; i < 96; i++) {
		if (outA[i] != expected_A[i]) {
			report_mismatch("A", i, expected_A[i], outA[i]);
			errors++;
		}
	}
	for (int i = 0; i < 64; i++) {
		if (outB[i] != expected_B[i]) {
			report_mismatch("B", i, expected_B[i], outB[i]);
			errors++;
		}
	}

	stack_use_1();
	stack_use_2();
	print_uart("stack aliasing calls done\n");
	for (int i = 0; i < 32; i++) {
		if (out_stack2[i] != expected_stack2[i]) {
			report_mismatch("stack2", i, expected_stack2[i], out_stack2[i]);
			errors++;
		}
	}

	if (errors == 0) {
		print_uart("Keccak interleaved-context test terminated with no errors.\n");
	} else {
		print_uart("Keccak interleaved-context test terminated with ");
		print_uart_dec(errors);
		print_uart(" errors\n");
	}

	return 0;
}
