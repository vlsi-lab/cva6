# HAWK-256 KeyGen/Verify cycle profiling (Keccak+Gauss-accelerated build)

This directory is a cycle-profiling variant of `tests/hawk-256-keccak`
(the Keccak-AXI + HW Gaussian-sampler accelerated build): identical HAWK
sources, with `PROF_BEGIN`/`PROF_END` instrumentation (from
`tests/hawk-256-profiling/profiling.h`) merged in to break KeyGen and
Verify down into their internal sub-phases. Its purpose was to answer:
now that SHA3/SHAKE is offloaded to hardware, what actually dominates
KeyGen and Verify?

## How to run

```
bash tests/hawk-256-keccak-profile/run.sh
```

`PROF_LEVEL` (env var, default 2) controls instrumentation depth:
`0` = none, `1` = L1 (top-level sub-functions), `2` = L1+L2
(sub-sub-functions). Output goes to the simulated UART, same as the
plain `tests/hawk-256-keccak/run.sh` KAT.

## Results (2026-07-21 run, full HAWK-256 KAT, all phases OK)

Top-level (matches `tests/hawk-256-keccak`'s numbers, modulo run-to-run
noise from the profiling reads themselves):

| Phase  | Cycles    |
|--------|----------:|
| KeyGen | 8,779,383 |
| Sign   |   325,396 |
| Verify |   562,324 |

### KeyGen breakdown

`Zh(keygen)`'s retry loop calls `Hawk_keygen` once (which internally
retries candidate (f,g) pairs until one satisfies every constraint),
then `encode_public`/`encode_private` once each on success.

| Sub-phase                                                              | Cycles    | Share of KeyGen |
|--------------------------------------------------------------------------|----------:|----:|
| `solve_NTRU` (NTRU-equation lattice-reduction solver, `ng_ntru.c`)       | 7,016,741 | **80%** |
| everything else in the retry loop (candidate gen, parity/norm checks, invertibility checks mod p1/p2, constant-term check) | ~1,371,000 | 16% |
| `make_q001` (computes q00/q01/q11 from the accepted f,g,F,G)              |   365,667 |  4% |
| `encode_public`                                                           |    14,760 | 0.2% |
| `encode_private`                                                          |     5,304 | 0.06% |

`solve_NTRU` alone is 80% of KeyGen. It is implemented in `ng_ntru.c`,
which internally calls `mp_NTT`/`mp_iNTT`/`mp_montymul` **108 times** —
the same modular-NTT/Montgomery-multiplication primitives (from
`ng_mp31.c`) used by Verify's `vrfy_ntt_norm` below.

### Verify breakdown

`Zh(verify)` calls `decode_public_key`/`decode_signature` (only exercised
when the caller passes encoded buffers — not on the direct-struct KAT
path) then `verify_inner`.

| Sub-phase                                                | Cycles  | Share of Verify |
|-----------------------------------------------------------|--------:|----:|
| `vrfy_ntt_norm` (NTT-based norm check mod primes P1, P2)  | 429,381 | **76%** |
| `vrfy_q01_fft`                                             |  29,082 |  5% |
| `vrfy_div_ifft`                                            |  27,151 |  5% |
| `vrfy_q00_fft`                                             |  23,650 |  4% |
| `vrfy_t1_fft`                                              |  22,325 |  4% |
| `vrfy_s0_t0`                                               |   6,065 |  1% |
| `vrfy_shake` (all 3 SHAKE256 calls: H(pub), hm, h)         |   5,782 |  1% |
| (unaccounted: Golomb-Rice/bit decode glue not covered by a marker) | ~16,800 | 3% |
| `verify_inner` total                                       | 560,275 | 99.6% |

`vrfy_ntt_norm` alone is 76% of Verify. SHAKE is only ~1%.

## Conclusion

SHA3/SHAKE was never the bottleneck for KeyGen or Verify — consistent
with their low Keccak call counts (148 and 6 respectively, vs. Sign's 47
call-heavy `sig_gauss`). The real bottlenecks are the *non-hash*
arithmetic:

- **KeyGen**: `solve_NTRU`'s lattice-reduction solver (`ng_ntru.c`).
- **Verify**: `vrfy_ntt_norm`'s NTT-based norm check (`hawk_vrfy.c`).

Both are built on the same underlying kernel — modular NTT butterflies
and Montgomery multiplication mod two small (~31-bit) primes, from
`ng_mp31.c`. A single small, fixed-modulus NTT/Montgomery-multiply
hardware unit could accelerate both simultaneously, making it a much
higher-leverage target than treating them as separate problems — see
the ongoing investigation into reusing the Keccak accelerator's 1600-bit
state register file as scratch storage for such a unit.
