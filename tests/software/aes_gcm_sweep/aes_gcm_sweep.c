// AES-128-GCM payload-size sweep: same KEY/IV/AAD as tests/*/aes_gcm,
// varying only the payload length, to see how the software/accelerated
// cycle gap changes with payload size. AAD is fixed at 20 B throughout
// (same value as tests/*/aes_gcm) -- AAD size only adds GHASH cost, not
// AES-CTR cost, so payload size (which drives both) is the more
// interesting axis for this sweep, per the paper's focus.
//
// Sizes are chosen to fit comfortably under this simulator's cycle
// watchdog even when run.sh raises it well above default (see
// corev_apu/tb/rvfi_tracer.sv's `+time_out` plusarg) -- software GCM is
// GHASH-dominated and slow to simulate at large sizes, so this sweep tops
// out at 1024 B rather than pushing toward realistic TLS-record sizes.
//
// Unlike tests/*/aes_gcm (which checks ciphertext/tag against an
// independently-computed KAT at one fixed size), this test checks
// self-consistency at each size (decrypt(encrypt(PT)) == PT, tag
// verifies) instead of maintaining a separate KAT per size -- the
// underlying aes128_gcm_encrypt/decrypt primitives are already
// KAT-validated by tests/*/aes_gcm; this sweep only needs to confirm they
// behave correctly across a size range, which a round-trip check gives
// without a large table of independently-derived expected ciphertexts.
// Identical source on the software and tightly trees -- only the linked
// aes_gcm.c/ghash.c/aes128_block.c implementations differ, per run.sh.

#include <string.h>
#include "uart.h"
#include "encoding.h"
#include "bench.h"
#include "aes_gcm.h"

static const uint8_t KEY[16] = {
    0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b,
    0x0c, 0x0d, 0x0e, 0x0f,
};

static const uint8_t IV[12] = {
    0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b,
};

static const uint8_t AAD[20] = {
    0xa0, 0xa1, 0xa2, 0xa3, 0xa4, 0xa5, 0xa6, 0xa7, 0xa8, 0xa9, 0xaa, 0xab,
    0xac, 0xad, 0xae, 0xaf, 0xb0, 0xb1, 0xb2, 0xb3,
};

#define MAX_LEN 1024
static const unsigned SIZES[] = {16, 64, 256, 1024};
#define NUM_SIZES (sizeof(SIZES) / sizeof(SIZES[0]))

static uint8_t PT[MAX_LEN];
static uint8_t buf[MAX_LEN];

int main()
{
  int errors = 0;

  // Deterministic, non-trivial fill pattern (not all-zero, not periodic
  // with the 16-byte AES block size).
  for (unsigned i = 0; i < MAX_LEN; i++) PT[i] = (uint8_t)(i * 37 + 11);

  printf("AES-128-GCM Payload-Size Sweep - 20 B AAD, payload 16..1024 B\n");

  BENCH_ENABLE();

  for (unsigned s = 0; s < NUM_SIZES; s++) {
    unsigned len = SIZES[s];
    uint8_t tag[16];
    unsigned long enc_cycles, enc_instrs, dec_cycles, dec_instrs;

    memcpy(buf, PT, len);

    BENCH_START();
    aes128_gcm_encrypt(KEY, IV, AAD, sizeof(AAD), buf, len, tag);
    BENCH_READ(enc_cycles, enc_instrs);

    BENCH_START();
    int rc = aes128_gcm_decrypt(KEY, IV, AAD, sizeof(AAD), buf, len, tag);
    BENCH_READ(dec_cycles, dec_instrs);

    if (rc != 0) {
      printf("!!! size=%u: tag verification failed (rc=%d) !!!\n", len, rc);
      errors++;
    }
    for (unsigned i = 0; i < len; i++) {
      if (buf[i] != PT[i]) {
        printf("!!! size=%u: plaintext mismatch at byte %u: expected 0x%02x, got 0x%02x !!!\n",
               len, i, PT[i], buf[i]);
        errors++;
        break;
      }
    }

    // Fixed-point bits/cycle (this platform's minimal sprintf() has no
    // %f support -- same convention as tests/*/aes_gcm).
    unsigned long enc_bpc_e4 = (8UL * len * 10000UL) / enc_cycles;
    unsigned long dec_bpc_e4 = (8UL * len * 10000UL) / dec_cycles;
    printf("size=%u encrypt_cycles=%lu encrypt_instrs=%lu encrypt_bpc=%lu.%04lu "
           "decrypt_cycles=%lu decrypt_instrs=%lu decrypt_bpc=%lu.%04lu\n",
           len, enc_cycles, enc_instrs, enc_bpc_e4 / 10000, enc_bpc_e4 % 10000,
           dec_cycles, dec_instrs, dec_bpc_e4 / 10000, dec_bpc_e4 % 10000);
  }

  if (errors == 0) printf("AES-128-GCM Payload-Size Sweep terminated with no errors.\n");
  else              printf("AES-128-GCM Payload-Size Sweep terminated with %d errors\n", errors);

  return errors;
}
