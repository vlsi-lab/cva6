// KMAC256 (NIST SP 800-185), implemented directly per spec on top of the
// shake256_* incremental API from fips202.h. Identical source on both the
// software and tightly trees.

#include <string.h>
#include "kmac.h"
#include "fips202.h"

// left_encode(x): 1 length byte (n) followed by the n bytes of x, big-endian,
// minimal encoding. x == 0 encodes as a single zero byte (n = 1).
static size_t left_encode(uint8_t *buf, uint64_t x)
{
  uint8_t rev[8];
  int n = 0;
  uint64_t t = x;
  do {
    rev[n++] = (uint8_t)(t & 0xFF);
    t >>= 8;
  } while (t);

  buf[0] = (uint8_t)n;
  for (int i = 0; i < n; i++)
    buf[1 + i] = rev[n - 1 - i];
  return 1 + n;
}

// right_encode(x): the n bytes of x, big-endian, minimal encoding, followed
// by the 1 length byte (n).
static size_t right_encode(uint8_t *buf, uint64_t x)
{
  uint8_t rev[8];
  int n = 0;
  uint64_t t = x;
  do {
    rev[n++] = (uint8_t)(t & 0xFF);
    t >>= 8;
  } while (t);

  for (int i = 0; i < n; i++)
    buf[i] = rev[n - 1 - i];
  buf[n] = (uint8_t)n;
  return n + 1;
}

// encode_string(S) length prefix = left_encode(bitlen(S)); caller absorbs S
// itself right after.
static size_t encode_string_prefix(uint8_t *buf, size_t slen)
{
  return left_encode(buf, (uint64_t)slen * 8);
}

#define CSHAKE_RATE 136  // SHAKE256_RATE, cSHAKE256/KMAC256's bytepad width

// Absorbs bytepad(hdr || payload, CSHAKE_RATE): hdr then payload then
// zero-padding on the right to a multiple of CSHAKE_RATE bytes.
static void absorb_bytepad(keccak_state *state,
                            const uint8_t *hdr, size_t hdr_len,
                            const uint8_t *payload, size_t payload_len)
{
  static const uint8_t zeros[CSHAKE_RATE] = {0};
  shake256_absorb(state, hdr, hdr_len);
  if (payload_len) shake256_absorb(state, payload, payload_len);
  size_t total = hdr_len + payload_len;
  size_t pad = (CSHAKE_RATE - (total % CSHAKE_RATE)) % CSHAKE_RATE;
  if (pad) shake256_absorb(state, zeros, pad);
}

void kmac256(uint8_t *out, size_t outlen,
             const uint8_t *key, size_t keylen,
             const uint8_t *in, size_t inlen,
             const uint8_t *custom, size_t customlen)
{
  uint8_t hdr[2 + 4 + 9];  // left_encode(136) + encode_string("KMAC") + encode_string(S)'s length prefix
  size_t off;
  keccak_state state;

  shake256_init(&state);

  // cSHAKE prefix: bytepad(encode_string("KMAC") || encode_string(S), 136)
  static const uint8_t kmac_name[4] = {'K', 'M', 'A', 'C'};
  off = left_encode(hdr, CSHAKE_RATE);
  off += encode_string_prefix(hdr + off, sizeof(kmac_name));
  memcpy(hdr + off, kmac_name, sizeof(kmac_name));
  off += sizeof(kmac_name);
  off += encode_string_prefix(hdr + off, customlen);
  absorb_bytepad(&state, hdr, off, custom, customlen);

  // X = bytepad(encode_string(K), 136) || in || right_encode(L)
  off = left_encode(hdr, CSHAKE_RATE);
  off += encode_string_prefix(hdr + off, keylen);
  absorb_bytepad(&state, hdr, off, key, keylen);

  if (inlen) shake256_absorb(&state, in, inlen);

  off = right_encode(hdr, (uint64_t)outlen * 8);
  shake256_absorb(&state, hdr, off);

  shake256_finalize_domain(&state, 0x04);
  shake256_squeeze(out, outlen, &state);
}
