# falcon1024-opt — Falcon-1024 verify with CVA6 Keccak hardware acceleration

This is `tests/falcon1024/` (the plain, pure-software Falcon-1024 KAT) with
the Keccak-AXI accelerator (`vrf_ip/rtl/keccak_f.sv`/`keccak_dma_ctrl.sv`)
wired into `shake.c` via a hardware-resident-state dispatcher pattern.
Every call site keeps calling the same function names it always did
(`Zf(i_shake256_init/inject/flip/extract)`, via the `inner_shake256_*`
macros) — each is now a transparent dispatcher to hardware, so no caller
(`nist.c`, `common.c`'s `hash_to_point_vartime`, `rng.c`'s `prng_init`,
`sign.c`, `keygen.c`) needed to change.

## Run

```
bash tests/falcon1024-opt/run.sh
```

## Files changed vs. `tests/falcon1024/`, and what replaced what

| File | What was substituted |
|---|---|
| `shake.c` | Keccak-F1600 permutation (`process_block`) redirected to the Keccak-AXI peripheral; `Zf(i_shake256_*)` made hardware-resident (`shake_inject`/`shake_flip`/`shake_extract`, built for Falcon's SHAKE256-only, fixed-rate-136 context) |
| `vrfy.c` | Added `mq_NTT_hw()`/`mq_iNTT_hw()`, drop-in replacements for `mq_NTT()`/`mq_iNTT()` at Verify's two call sites (`Zf(to_ntt_monty)`, `Zf(verify_raw)`), dispatching to `ntt_engine.sv` — see "NTT/iNTT hardware offload" below |
| `common.c` | `Zf(hash_to_point_vartime)()`'s squeeze-compare-reduce rejection-sampling loop replaced with a single call to `Zf(hash_to_point_hw)()` (new, `shake.c`), dispatching to `rej_sampler.sv` — see "Hash-to-point rejection-sampler hardware offload" below |
| `inner.h` | Added `hw_seen` field to `inner_shake256_context` (residency-tracking flag); added `Zf(hash_to_point_hw)()` prototype |
| `falcon1024_optimized.c` (formerly `main.c`) | Added `falcon_ntt_dispatch_cycles`/`falcon_ntt_dispatch_calls`, `falcon_hash_to_point_cycles`/`_calls`, `falcon_is_short_cycles`/`_calls` reporting after "verify" |
| `run.sh` | Points at this directory's own sources instead of `tests/falcon1024/`'s, and adds `-I../../vrf_ip/sw` for `vrf_axi.h` |

## Why this was safe to wire in globally (not just for Verify)

`shake.c`'s `Zf(i_shake256_*)` functions are shared by KeyGen, Sign, and
Verify. Redirecting them to hardware unconditionally is safe here because:

- The residency machinery (`hw_owner`/`hw_seen`) transparently
  evicts/re-uploads whichever context last held the accelerator's
  registers, so interleaved use by different logical contexts (e.g.
  KeyGen's RNG context vs. Verify's hash-to-point context) is handled
  correctly regardless of call order.
- No caller in this tree does a raw struct copy/`memcpy` of a live
  `inner_shake256_context` (verified by grep across `sign.c`/`keygen.c`/
  `rng.c`) — the one place state is reused across calls,
  `Zf(prng_init)()`, goes through `inner_shake256_extract()`, which is
  hardware-safe by construction. Falcon verify has no chained reuse of a
  live shake state across separate sessions (see below), so no dedicated
  clone accessor was needed.

## Verify's hash chain, and what the hardware pattern buys it here

Falcon verify (`nist.c:crypto_sign_open`) runs a **single** SHAKE256
session per verify:

```
inner_shake256_init(&sc);
inner_shake256_inject(&sc, sm + 2, NONCELEN + msg_len);  /* nonce ‖ message, one call */
inner_shake256_flip(&sc);
Zf(hash_to_point_vartime)(&sc, hm, logn);                /* many 2-byte extracts */
```

The hardware payoff is inside `hash_to_point_vartime` (`common.c`): it
calls `inner_shake256_extract(sc, buf, 2)` in a tight rejection-sampling
loop (reject `w >= 61445`, ~6.25% of draws, then squeeze again) — for
`logn=10` that's on the order of ~1024×1.07 ≈ 1100 two-byte extracts,
which cross a 136-byte rate boundary roughly every 68 calls. The
resident-state design means only those ~16 block-boundary crossings pulse
a real Keccak-f permutation (`process_block_resident`, register poke +
poll); every other extract call is a pure SRAM/register readback with no
re-upload, because `hw_owner == sc` stays true across the whole loop. This
is the payoff of keeping the state resident in the accelerator instead of
re-absorbing/re-uploading between related calls, applied here to Falcon's
single long-extract session.

## NTT/iNTT hardware offload (`vrfy.c`)

`mq_NTT_hw()`/`mq_iNTT_hw()` (new, `vrfy.c`) replace `mq_NTT()`/`mq_iNTT()`
at Verify's two call sites (`Zf(to_ntt_monty)`'s pubkey transform,
`Zf(verify_raw)`'s `s2*h` computation), dispatching to `ntt_engine.sv` — a
generic 32-bit-domain Montgomery NTT/iNTT engine (`job_p_val_i`/
`job_p0i_val_i` are plain per-job register inputs, not a hardcoded prime),
reused here for Falcon's single prime `q=12289`.

**Domain note**: reading `ntt_engine.sv` directly (not assumed) shows the
engine already takes `p`/`p0i` as plain per-job registers, not a hardwired
prime pair — no RTL change was needed at all. The engine's Montgomery
reduction uses its own R=2^32 convention (`mp_montymul`), while Falcon's
native `mq_montymul` (`vrfy.c`, `GMb`/`iGMb`, `R2=10952`) uses a
*different*, bespoke R=2^16 reduction — reusing the engine required
generating an entirely separate x2^32-Montgomery twiddle table for
`q=12289` (`GM32[]`/`iGM32[]`, via the engine-generation helper
`mp_mkgmigm()`, Falcon's own `g=7`/`1/g=8778` roots re-encoded into the new
domain), not just pointing the existing `GMb`/`iGMb`/`Q0I` at new
registers.

The upside: since only the twiddle *table* carries the Montgomery R factor
(not the transformed data itself — `mq_NTT`/`mp_NTT` are domain-preserving:
a plain input polynomial produces a plain output NTT regardless of which
Montgomery convention the twiddles/reduction use internally), the
surrounding glue code (`mq_poly_tomonty`, `mq_poly_montymul_ntt`,
`mq_poly_sub`) needed **zero changes** — it keeps running Falcon's native
16-bit-domain `mq_montymul`/`R2=10952` exactly as the reference does,
completely unaware that the transform in between ran on different hardware
in a different numeric domain.

**Validation status**: `Test Successful` on the real CVA6 RTL simulator
(`bash tests/falcon1024-opt/run.sh verify`), 638,306 verify cycles, exactly
matching the earlier native-x86-cross-check-only figure in `results.md` —
also cross-checked bit-for-bit against Falcon's own `mq_NTT`/`mq_iNTT` in a
native x86 harness beforehand (400 random trials at `logn=9`/`logn=10`,
covering the forward transform alone, NTT/iNTT round-trip, and the exact
mixed-domain pipeline implemented here).

## Hash-to-point rejection-sampler hardware offload (`shake.c`, `common.c`)

`Zf(hash_to_point_hw)()` (new, `shake.c`) offloads
`Zf(hash_to_point_vartime)()`'s squeeze-compare-reduce loop (`common.c`) to
the `rej_sampler.sv` hardware unit (`vrf_ip/rtl/rej_sampler.sv`), a
sibling of `gauss_sampler.sv`/`ntt_engine.sv` sharing the same Keccak-AXI
squeeze-output bus, register-poke dispatch pattern
(`REJ_X_ADDR`/`REJ_PARAMS`/`REJ_CTRL`, `keccak.hjson`), and non-cacheable
DRAM scratch-window convention (`VRF_REJ_HW_SCRATCH_ADDR`, `shake.c`) as
every other hardware job in this tree — identical RTL and driver code to
`falcon512-opt`'s (see that directory's README for the full design
rationale); this port only changes `logn`/`n` (1024 instead of 512).

**Result**: `hash_to_point_vartime` dropped to 14,242 cycles, 2.9% of
verify; overall verify dropped from 638,306 (NTT/iNTT-only) to 490,765
cycles (×1.30 additional speedup; ×2.02 vs. the original fully-software
989,144) — see `results.md`. `Zf(is_short)`'s own share (2.3%, 11,375
cycles) was measured and found too small to be worth dedicated hardware,
so it was left in software, same conclusion as `falcon512-opt`.

**Validation status**: `Test Successful` on the real CVA6 RTL simulator —
correctness is verified by the KAT's own signature-verify pass/fail (a
wrong `hash_to_point` output would fail `Zf(is_short)`'s bound check and
the whole KAT), not just cycle-count plausibility.

## Not yet accelerated (stays software)

- **`mq_poly_montymul_ntt`'s pointwise multiply** (between `mq_NTT_hw`
  and `mq_iNTT_hw` in `Zf(verify_raw)`) stays a software loop over
  Falcon's native 16-bit `mq_montymul` — see "NTT/iNTT hardware offload"
  above for why this is correct as-is, not a gap; it was a deliberate
  choice to keep the mixed-domain boundary as small as possible; it could
  be moved onto the engine's own pointwise-multiply datapath in a later
  pass if profiling shows it's worth it.

## Design pattern

The Keccak-AXI wiring pattern (`hw_owner`/`hw_seen` residency tracking,
`keccak_dma_absorb_job` fresh/flip bits, `process_block_resident`) is
degree-generic, built for Falcon's simpler SHAKE256-only (fixed rate 136,
no `shake_init(size)` parameter) `inner_shake256_context`.
