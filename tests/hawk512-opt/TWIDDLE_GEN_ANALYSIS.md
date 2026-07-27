# HAWK KeyGen twiddle-table generation — deferred acceleration analysis (2026-07-26)

Split out of `NTT_ACCEL_DESIGN.md`'s PQNTRU-paper cross-analysis (see that
file's "PQNTRU paper cross-analysis" section for the full three-item
comparison this was item #3 of) because it is **confirmed KeyGen-only,
not on either HAWK's or Falcon's verify path** — the user's current
priority is accelerated verification, so this is written up here as a
scoped, ready-to-pick-up proposal for a future KeyGen-focused pass rather
than folded into the verify-focused design doc.

## The idea (from PQNTRU, §4.2.3)

Rather than pre-computing and storing every NTT twiddle factor (which the
paper's authors judge impractical for HAWK's many RNS moduli), store just
the primary root `ω1` and derive `ω2, ω3, ...` from it via repeated
modular multiplication — the paper does this with SIMD lanes; we would
do it with the multiplier already inside `ntt_engine.sv`.

## Why this maps cleanly onto what we already have

Checked directly against `ng_mp31.c`/`ng_inner.h`, not assumed:

- **`PRIMES[]`** (324 entries, `ng_inner.h`/`ng_mp31.c`) already stores
  exactly the "primary root" per modulus, as a compile-time constant:
  `{p, p0i, R2, g, ig, s}`. Half of the paper's precondition — "the
  primary twiddle factor is pre-computed and stored" — is already true.
- **The "derive the rest by multiplication" step is already exactly
  what our software does today, entirely unaccelerated.** `mp_mkgm()`'s
  non-AVX2 path (the only one CVA6 compiles — confirmed via
  `ng_config.h`'s `NTRUGEN_AVX2 = HAWK_AVX2 = 0` for this build) is a
  plain sequential loop:
  ```c
  uint32_t x1 = mp_R(p);
  size_t u = 0;
  for (;;) {
      size_t v = REV10[u << k];
      gm[v] = x1;
      u++;
      if (u >= n) break;
      x1 = mp_montymul(x1, g, p, p0i);
  }
  ```
  one software `mp_montymul()` call per output twiddle, `n` times.
- **`REV10[]` is a plain 10-bit bit-reversal** (checked its actual
  values: `REV10[1]=512, REV10[2]=256, REV10[3]=768, ...`) — a free wire
  permutation in hardware, not a lookup table needing its own ROM. The
  address side of an on-engine generator would cost nothing extra.
- **Not a rare cold path**: `mp_mkgm`/`mp_mkgmigm`/`mp_mkigm` are called
  from 18+ sites across `ng_hawk.c`, `ng_ntru.c`, `ng_poly.c` (grepped,
  not estimated), many inside `PRIMES[u]` RNS-prime loops that rebuild
  the table from scratch per modulus — this is not a one-time setup cost
  paid once per KeyGen call.

## Why it's deferred, not built now

Grepped directly, not inferred: **`hawk_vrfy.c` has zero calls to
`mp_mkgm`/`mp_mkgmigm`/`mp_mkigm`.** Falcon's `vrfy.c` GM32[]/iGM32[]
(the twiddle tables `mq_NTT_hw`/`mq_iNTT_hw` use) are `static const`
arrays baked in at build time — generated once, offline, by a one-time
call to `mp_mkgmigm()` during development (see `vrfy.c`'s own header
comment), not regenerated at verify runtime. Neither HAWK's nor Falcon's
verify path pays any twiddle-generation cost today, so accelerating it
does not move the number the user currently cares about. It stays a real
opportunity for HAWK KeyGen specifically.

## Measured cost

Instrumented (`ng_mp31.c`: `twiddle_gen_cycles`/`twiddle_gen_calls`
globals, wrapping `mp_mkgm()`/`mp_mkigm()`/`mp_mkgmigm()` bodies with
`read_csr(mcycle)`, same pattern as `ntt_dispatch_cycles`; printed by
`main.c` right after "Keygen OK" as `KeyGen (twiddle-gen)`) but **not
yet measured**: the `hawk512-opt` full KAT run needed to produce the
number (KeyGen alone is ~60M cycles, ~2+ hours of Verilator wall-clock
time on this machine) was interrupted twice by unrelated environment
issues before completing — not worth a third multi-hour attempt given
this is already deferred, lower-priority work relative to the user's
current verify-focused acceleration effort. The instrumentation is in
place and ready to run (`bash tests/hawk512-opt/run.sh`) whenever this
becomes the active priority; look for the `KeyGen (twiddle-gen): N
calls, C cycles (P% of phase)` line in the UART output.

## Proposed hardware, once prioritized

A new `ntt_engine.sv` job mode reusing the multiplier already shared 3×
per butterfly (`mm_opA`/`mm_opB`/`mm_prod`), given `g` (or `ig`), `p`,
`p0i`, `n`: self-index through `u = 0..n-1`, each step computing
`x1 = montymul(x1, g)` and writing `gm[bitreverse(u)] = x1` to DRAM (bit
reversal wired combinationally, no ROM). This moves an O(n) chain that
today costs a full software `mp_montymul()` call per step onto a
purpose-built pipeline, and removes it from the CPU critical path
entirely for KeyGen. Not scoped further (register map, FSM states, DRAM
write cadence) until the measured cost above justifies the effort.
