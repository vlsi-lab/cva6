# Falcon Verify — Baseline vs. Hardware-Accelerated

Cycle counts for the `verify` phase only (`./run.sh verify`), measured via the
RISC-V `mcycle` CSR on the CVA6 `cv64a6_imac_crypto` target (Verilator
`veri-testharness` RTL simulation), single KAT vector (`N_KAT=1`).

- **Baseline** = `tests/pqc/baseline/falcon{512,1024}` — reference PQClean-style
  software implementation, no hardware offload.
- **Accelerated** = `tests/pqc/optimized/falcon{512,1024}` — SHAKE256/Keccak-F1600
  offloaded to the Keccak AXI accelerator, plus NTT/iNTT hardware dispatch and
  an optimized rejection sampler in the verify path.

## Results

| Algorithm    | Baseline (cycles) | Accelerated (cycles) | Cycles saved | Speedup |
| ------------ | -----------------: | --------------------: | ------------: | ------: |
| Falcon-512   |            473,803 | 229,864               |      243,939 |  2.061× |
| Falcon-1024  |            989,155 | 491,048               |      498,107 |  2.014× |

> **Speedup definition:** baseline cycle count ÷ accelerated cycle count.

## Source logs

| Algorithm / config    | Log                                                                                   |
| ---------------------- | -------------------------------------------------------------------------------------- |
| Falcon-512 accelerated | `verif/sim/out_2026-08-03/veri-testharness_sim/falcon512_optimized.cv64a6_imac_crypto.log.iss` |
| Falcon-1024 baseline    | `verif/sim/out_2026-08-03/veri-testharness_sim/falcon1024_baseline.cv64a6_imac_crypto.log.iss` |
| Falcon-1024 accelerated | `verif/sim/out_2026-08-03/veri-testharness_sim/falcon1024_optimized.cv64a6_imac_crypto.log.iss` |

## Caveats

- **Falcon-512 baseline (473,803 cycles) is not from today's run.** Today's
  `falcon512_baseline.cv64a6_imac_crypto.log.iss` has no `Clock cycles [verify]`
  line — it recorded 9,765,283 total RTL cycles (10–40× the other three runs)
  and ~20.7 CPU-minutes, consistent with a stale/interrupted `keygen+sign+verify`
  ("all") run rather than a clean, isolated `verify` run, so no reliable verify-only
  number could be read from it. The value used here is carried over from this
  repo's existing `results.md` (prior session); it was not re-measured today.
  It lines up closely with today's other three numbers versus their prior-session
  counterparts (all within ~0.1%), so it's very likely still accurate, but it
  should be re-verified with a clean `./tests/pqc/baseline/falcon512/run.sh verify`
  run before being relied on for anything precision-sensitive.
- All three fresh numbers (Falcon-512 accelerated, Falcon-1024 baseline,
  Falcon-1024 accelerated) matched this repo's pre-existing `results.md` fully-optimized
  figures (230,116 / 490,765) and baseline figure (989,144) within ~0.1%,
  cross-confirming both today's measurements and the prior ones.
- Single KAT vector per run (`N_KAT=1`); not averaged across multiple vectors.

---

# 2026-08-06 — `vrf_ip` merge (Falcon + SPHINCS+ hash-chain on one shared Keccak core)

`falcon_ip` and `hashpq_ip` were merged into a single `vrf_ip` accelerator: one
`keccak_f` permutation core now serves four job front-ends (DMA-absorb/CSREG,
NTT/iNTT, rejection sampler, and the new SPHINCS+ hash-chain job
`chain_job_ctrl`, which replaces `hashpq_ip`'s standalone `chain_accel` and its
duplicate Keccak core entirely). All numbers below are real `veri-testharness`
RTL simulation runs from today, measured via the RISC-V `mcycle` CSR, `cv64a6_imac_crypto`
target.

## Falcon regression (confirms the merge didn't disturb the existing path)

| Test                    | SW (cycles) | HW (cycles) | Speedup | Result |
| ------------------------ | ----------: | ----------: | ------: | :----: |
| `ntt` (n=512)             |      86,375 |      49,644 |  1.740× | PASS   |
| `intt` (n=512)            |      93,837 |      47,938 |  1.957× | PASS   |
| `keccak-abs-shake256`     |      12,110 |       1,477 |  8.200× | PASS   |
| `falcon512` full verify   | 473,803¹    | **229,864** |  2.061× | PASS   |

¹ Baseline not re-run today (see 2026-08-03 caveat above); the accelerated
figure (229,864 cycles) is a fresh measurement and is bit-for-bit identical to
the pre-merge figure recorded above, confirming no regression from the
`falcon_ip`→`vrf_ip` rename/merge.

## New: SPHINCS+/SLH-DSA hash-chain job (`chain_job_ctrl`, via the shared Keccak core)

These primitives (THASH1/THASH2/PRF_ADDR, simple + robust NIST constructions,
n = 16/24/32 bytes) were previously unreachable: `hashpq_ip`'s standalone
`chain_accel` was never wired to real software and its own standalone tests
were marked "known to hang indefinitely." Today's work found the actual root
cause (a missing `-fno-tree-loop-distribute-patterns` compile flag causing a
pre-`main()` hang unrelated to the hardware — see below), fixed it, and wired
the primitive onto the shared Keccak core for the first time. All four
standalone tests now pass in full on real RTL simulation:

| Test                        | Cases | SW (cycles) | HW (cycles) | Speedup  | Result |
| ---------------------------- | ----: | ----------: | ----------: | -------: | :----: |
| `prf-addr` (PRF_ADDR)         |   6/6 |      64,154 |       1,408 |  45.56×  | PASS   |
| `thash` (THASH1)               |  12/12 |     190,857 |       2,980 |  64.05×  | PASS   |
| `thash2` (THASH2)               |  12/12 |     195,356 |       3,706 |  52.72×  | PASS   |
| `thash-wots` (THASH1 + 6-step WOTS+ chain) | 24/24 | 663,710 | 4,360 | 152.23× | PASS   |

`thash-wots` includes a single `chain_job_ctrl` MMIO call that runs a full
6-step WOTS+ hash chain internally (`CHAIN_CTRL.STEPS=6`) instead of 6
separate software-driven calls — that internal chaining is most of where the
152× figure comes from (123,419 SW cycles vs. 562 HW cycles for one 6-step
chain at the 128f-robust level alone).

## Root causes found and fixed today (not assumed, diagnosed via real sim runs)

1. **Pre-existing hang, misdiagnosed at first.** Initial hypothesis (from static
   analysis before any RTL was touched) was that `hashpq_ip`'s AXI bridge
   (`chain_axi_top`'s `axi2mem`-based path) was the cause. After building
   `chain_job_ctrl` on the already-proven `axi_to_reg` bridge instead, the
   *same* symptom (continuous AXI "B Response Errored" writes, CPU never
   reaching `main()`) still occurred. Root cause turned out to be unrelated to
   either AXI bridge: `prf-addr`/`thash`/`thash2`/`thash-wots`'s `run.sh`
   scripts were the only ones in `tests/app-tests/` missing
   `-fno-tree-loop-distribute-patterns`, letting GCC silently rewrite a loop
   into a `memset`/`memcpy` call that misbehaves in this `-nostartfiles`
   freestanding build, hanging before `main()` ever runs. Added the flag to
   all four `run.sh` scripts.
2. **Test bug (not RTL):** `thash`/`thash-wots` hardcoded `step_start=0` for
   plain (non-chained) THASH1 calls. `chain_job_ctrl.sv` deliberately overlays
   the job's step counter (seeded from `CHAIN_CTRL.STEP_START`) into ADRS byte
   31 for every THASH1 job — by design, documented — so the test needs to pass
   the real `addr[31]` as `step_start` to match the software reference, which
   uses the address buffer verbatim. Fixed in both test files.

---

# 2026-08-06 (continued) — Phase 1: ML-DSA hardware primitives

Three `vrf_ip` primitives were extended to support ML-DSA (Dilithium),
alongside their existing Falcon/SPHINCS+ use, and each was validated on real
`veri-testharness` RTL simulation with a new standalone `tests/app-tests/`
test before moving to the next. All three additions default to the prior
(Falcon) behavior when their new control bits are left at 0, so no existing
software had to change.

## `ntt_engine.sv`: NTT_CTRL.NOSCALE (ML-DSA inverse-transform convention)

Falcon's `mp_iNTT` distributes the n⁻¹ scaling via `mp_half` on every
butterfly of every stage; ML-DSA's reference `invntt_tomont()` does no
per-stage scaling at all and applies one combined correction multiply in
software afterward. `NTT_CTRL.NOSCALE=1` skips the per-stage half so the
engine can serve either convention.

Validated by `tests/app-tests/ntt-mldsa`: a self-consistent forward+inverse
round trip at ML-DSA's actual modulus (q=8380417, n=256, ~23-bit vs.
Falcon's ~14-bit), using a twiddle table derived at runtime from ML-DSA's
own primitive root (g=1753, ML-DSA's `ROOT_OF_UNITY`) — not borrowed from
Falcon's tables, so an arithmetic-width or control-bit bug would show up as
a genuine round-trip failure, not a self-fulfilling pass.

| Check | Result |
| --- | :---: |
| p0i = -1/q mod 2^32 self-check | PASS |
| Forward + inverse(NOSCALE) + software n⁻¹ round trip (256 coefficients) | PASS |

HW cycles for both transforms combined: 49,177 (no SW baseline measured here
— this test validates correctness of the widened arithmetic and the new
control path, not a cycle comparison; Falcon's own `ntt`/`intt` cycle
comparisons above are unaffected, confirming NOSCALE=0 is bit-identical to
the prior behavior).

## `rej_sampler.sv`: REJ_CTRL.CAND3/RATE168/OUTWIDE (ML-DSA `rej_uniform`)

Falcon's `hash_to_point_vartime` draws 2-byte big-endian candidates
(unmasked, `thresh=5*q`, SHAKE256, uint16_t output); ML-DSA's `rej_uniform`
draws 3-byte little-endian candidates (masked to 23 bits, `thresh=q`,
SHAKE128, int32_t output). `Q`/`THRESH` were widened from 16 to 24 bits;
`CAND3`/`RATE168`/`OUTWIDE` select ML-DSA's convention per job. The
accept/reduce math itself needed no change (the existing bounded
conditional-subtract reduction is a correct no-op when the masked candidate
is already below `q`, true by construction for ML-DSA's `thresh=q`).

Validated by `tests/app-tests/rej-mldsa`: a from-scratch SHAKE128 +
`rej_uniform` software reference (independent Keccak-f[1600] + sponge
implementation, not shared code with the HW driver) compared against one
`rej_sampler` HW job with all three new mode bits set.

| Test | Samples | SW (cycles) | HW (cycles) | Speedup | Result |
| --- | ---: | ---: | ---: | ---: | :---: |
| `rej-mldsa` | 64/64 | 50,353 | 1,559 | 32.30× | PASS, 0 mismatches |

Falcon regression: `tests/pqc/optimized/falcon512` full verify (which
exercises the *original* 16-bit/big-endian/SHAKE256/uint16_t path through
this same widened module) still passes its KAT (`*** SUCCESS ***`,
tohost=0) after the rewrite, at 229,932 cycles vs. the 229,864-cycle
pre-rewrite baseline — a +68 cycle (+0.03%) difference. Correctness is
fully preserved; the small cycle delta was not chased further given its
size, but is noted here rather than silently rounded away.

## `keccak_dma_ctrl.sv`: JOBCTRL.RATE168 (SHAKE128 absorb, for ML-DSA matrix-A expansion)

The DMA absorb engine's rate boundary (previously a hardcoded 136-byte
SHAKE256 `localparam`) is now a per-job register selecting 136 (SHAKE256) or
168 bytes (SHAKE128) — the block-wrap trigger and the FLIP padding's
last-byte position are both re-derived from the selected rate at runtime.

Validated by `tests/app-tests/keccak-abs-shake128`: non-incremental SHAKE128
(absorb-once + squeeze) via the DMA job engine with `RATE168=1`, using a
200-byte message (exercises the multi-block *absorb* path, >168 bytes) and a
336-byte squeeze (exercises the multi-block *squeeze* path, >168 bytes),
against an independent public-domain Keccak-f[1600]+SHAKE128 software
reference.

| Test | SW (cycles) | HW (cycles) | Speedup | Result |
| --- | ---: | ---: | ---: | :---: |
| `keccak-abs-shake128` | 34,508 | 6,116 | 5.64× | PASS, byte-exact (336 bytes) |

Falcon regression: `keccak-abs-shake256` (the original SHAKE256/rate=136
path through this same module) is bit-for-bit unchanged: 12,110/1,477
cycles, identical to its pre-Phase-1 measurement.

## One real bug found and fixed during this phase

`keccak_dma_ctrl.sv`'s first draft used inline part-selects on a
parenthesized expression (`(rate_bytes_l - 8'd1)[7:3]`), which Verilator
rejects as a syntax error (`unexpected '['`) — caught immediately by the
`keccak-abs-shake256` regression run failing to even verilate, before any
simulation. Fixed by introducing an intermediate `rate_last_byte` signal.

## 2026-08-07 — Phase 2: `tests/vrf` restructured to verify-only (all 11 schemes, 22 variants)

`tests/vrf/{baseline,optimized}/<scheme>` was, until this phase, a byte-identical
copy of `tests/pqc` (full keygen+sign+verify). Every `main.c`/driver file across
all 11 schemes (Falcon-512/1024, ML-DSA-44/65/87, SPHINCS-{128f,192f,256f}-
{robust,simple}) was rewritten to run **only** `crypto_sign_open`/
`crypto_sign_verify`, loading the KAT's own pk/sm directly instead of generating
them, and printing both `mcycle` and `minstret` deltas for the verify call.

### Real bugs found and fixed while wiring this up (not assumed correct — checked)

1. **All 22 `tests/vrf` `run.sh` files pointed at `tests/pqc/...` instead of the
   local `tests/vrf/...` directory.** This meant the verify-only `main.c`
   rewrites (Falcon, ML-DSA, SPHINCS+) had never actually been exercised by
   their own `run.sh` — running any of them would silently build and run the
   *old* full keygen+sign+verify sources from `tests/pqc` instead. Fixed by
   redirecting every `src_main`/`src_incs`/`-I` path to `tests/vrf`. Falcon's
   `run.sh` additionally still carried a dead `keygen|sign|verify|all` phase
   selector and `-DRUN_KEYGEN/SIGN/VERIFY` flags left over from the old
   full-harness template, which no longer apply to the verify-only rewrite;
   removed.

2. **All 6 optimized SPHINCS+ variants had `fips202.c`, `hash_shake.c`,
   `thash_shake_{robust,simple}.c`, and `wots.c` rewritten to call a fictional
   custom-instruction interface** (`keccak_hw_*`, `cus_load*`/`cus_store`,
   `chain_lengths_hw_*`) with no implementation anywhere reachable in this
   repo (a `keccak_coproc.S` defining only some of the referenced symbols, and
   a `chain_lengths_hw.h` — both dead ends, confirmed during Phase 0's
   investigation). This was previously believed (from an earlier, incomplete
   investigation) to be scoped to `SPHINCS-128f-robust` only; a full
   file-by-file diff against baseline this phase showed it was present in
   **all 6** optimized variants. Restored all 5 files from the clean baseline
   source per variant; deleted `keccak_coproc.S`/`chain_lengths_hw.h` and the
   `run.sh` block that compiled the former in. Real HW-driver integration for
   SPHINCS+ is deferred to Phase 3, same as ML-DSA — Phase 2 keeps algorithm
   files stock, only the verify-only `main.c` differs from baseline.

3. **The "simple" SPHINCS+ variants' baseline `run.sh` (128f/192f/256f)
   referenced a nonexistent `thash_shake_robust.c`** instead of the actual
   `thash_shake_simple.c` present in their nested `src/` — a copy-paste
   artifact from the robust template. Fixed in all 3.

4. **All 12 `tests/vrf/{baseline,optimized}/SPHINCS-*/run.sh`** additionally had
   the `TESTS_ROOT` up-count wrong (5 levels instead of 3, matching this
   directory's actual depth) and `TEST_DIR` pointing at a nonexistent
   `tests/pqc/{baseline,optimized}/DS/SLH-DSA/SPHINCS-*` subpath instead of
   `tests/vrf/{baseline,optimized}/SPHINCS-*` directly. Fixed.

5. **ML-DSA and every SPHINCS+ variant's driver file was named `main.c`.**
   cva6.py derives both the compiled artifact name (`directed_tests/main.o`)
   and the simulation log name (`main.c<target>.log.iss`) from the source
   basename — so running any two of these variants back-to-back (or
   concurrently) silently clobbered the previous run's compiled binary and
   log before it could be read. Falcon was unaffected (its driver files are
   already named per-variant, e.g. `falcon512_baseline.c`). Fixed by renaming
   all 18 ML-DSA/SPHINCS+ driver files to the same `<variant>_<kind>.c`
   convention Falcon already used, and updating the corresponding `run.sh`
   `src_main` lines. This also incidentally fixed the compiled-artifact
   collision, enabling safe concurrent runs of different variants.

### Validation

All 22 variants cross-compile and link cleanly (`riscv-none-elf-gcc`, matching
each `run.sh`'s actual flags). A representative subset was run end-to-end on
real RTL simulation (`veri-testharness`/Verilator + spike ISS):

| Test | Cycles [verify] | Instructions [verify] | Result |
| --- | ---: | ---: | :---: |
| `falcon512` baseline | 473,731 | 419,447 | `*** SUCCESS ***` |
| `falcon512` optimized (vrf_ip HW offload) | 230,112 | 120,346 | `*** SUCCESS ***`, 2.06× vs. baseline |
| `ML-DSA-44` baseline (= current optimized, byte-identical code) | 1,504,523 | 1,296,187 | `*** SUCCESS ***` |

The `ML-DSA-44` run above was launched as `optimized-ML-DSA-44`, but since
`tests/vrf/optimized/ML-DSA-44` is currently byte-identical to
`tests/vrf/baseline/ML-DSA-44` (confirmed via `diff -rq`, no `vrf_axi.h`/
`VRF_*`/`NTT_CTRL`/`REJ_CTRL`/`JOBCTRL` references anywhere in its sources —
Phase 3 hasn't wired anything in yet), this number **is** the ML-DSA-44
software baseline and is recorded as such here. A separate
`baseline-ML-DSA-44` RTL run was attempted earlier in this same session but
its result was lost to the `main.c` filename collision (see bug #5 above,
fixed after that run) before it could be read — re-running it now would only
reproduce the identical number, so it was not repeated.

`optimized-SPHINCS-128f-robust` was launched but not waited on: SPHINCS+
verify is hash-heavy (WOTS+/FORS/Merkle, no HW offload yet either) and takes
on the order of hours in cycle-accurate Verilator simulation regardless of
baseline vs. optimized (both run identical, unaccelerated software until
Phase 3). Its result will be recorded once available.

Note `ML-DSA-44` and `SPHINCS-128f-robust`'s numbers above are software-only
baselines, not evidence of hardware acceleration — Phase 3 (wiring the real
`vrf_ip` NTT/rejection-sampler/chain-job drivers into the ML-DSA and
SPHINCS+ algorithm code, following the template already established by
Falcon's `optimized/falcon512/{shake.c,vrfy.c}`) has not
started.

## 2026-08-07 (continued) — Phase 3 prep: ML-DSA NTT twiddle-table derivation, verified bit-exact

Before wiring `ntt_engine.sv` into real ML-DSA verify code, the open question
flagged in Phase 1 (and in `ntt-mldsa`'s own header comment) needed resolving:
does the HW engine's twiddle-table indexing convention actually match
ML-DSA's real `zetas[]` table, or merely produce a self-consistent forward/
inverse pair unrelated to the real reference? A self-consistent round trip
(Phase 1's original `ntt-mldsa` test) cannot distinguish these — pointwise
multiplication steps in real ML-DSA verify (`polyvec_matrix_pointwise_montgomery`,
etc.) combine HW-NTT'd and software-NTT'd operands, so bit-exact agreement
with the real transform is required, not just invertibility.

Derived from `ntt_engine.sv`'s address-generator RTL directly (`twiddle_idx =
outer_q + u_q`, `outer_q`/`u_q` progression per stage) and matched
symbolically against `ntt()`/`invntt_tomont()`'s exact loop-nest traversal
(`tests/vrf/optimized/ML-DSA-44/ntt.c`):

- **Forward**: `gm[idx] = zetas[idx] mod Q` — the real `zetas[]` table used
  directly, no reordering. Confirmed: RTL's stage/index progression visits
  the exact same sequence, in the exact same order, as software's
  `zeta = zetas[++k]`.
- **Inverse**: `igm[idx] = (Q - zetas[idx XOR (bitfloor(idx)-1)]) mod Q`,
  where `bitfloor(idx)` is the largest power of two <= idx. RTL's `outer_q`
  (hm) descends per stage while `u_q` ascends, but software's `k` descends
  as `start` ascends within the same stage — same index *set* per stage,
  reversed *order*, which resolves to a bit-complement of the low bits
  within each power-of-two block.

Both formulas were checked two ways before being used in any test: (1) a
pure host-side C program simulating both the RTL's exact (stage, u)
traversal and software's exact (len, start, k) traversal position-by-position
— 0/255 mismatches; (2) `tests/app-tests/ntt-mldsa` was rewritten (from a
self-consistent round trip) to run ML-DSA's actual `ntt()`/`invntt_tomont()`
(byte-for-byte copies, including `montgomery_reduce`/`QINV`) as the reference
and compare bit-exact against HW forward/inverse output, run on real RTL.

| Test | Forward vs. `ntt()` | Inverse vs. `invntt_tomont()` | HW cycles (both) |
| --- | :---: | :---: | ---: |
| `ntt-mldsa` (rewritten) | PASS, bit-exact | PASS, bit-exact | 115,520 |

Both tables are fixed (n=256 for every ML-DSA security level) and are the
exact tables Phase 3's real driver will embed — no further primitive-level
uncertainty remains for the NTT portion of ML-DSA verify offload.

## 2026-08-08 — Phase 3: real HW driver integration for ML-DSA and SPHINCS+ verify

Real hardware dispatch wired into `tests/vrf/optimized/{ML-DSA-*,SPHINCS-*}`,
replacing the pure-software `crypto_sign_open`/`crypto_sign_verify` code
paths validated in Phase 2. Every change keeps the original function
signatures (`ntt()`, `invntt_tomont()`, `poly_uniform()`, `thash()`,
`gen_chain()`), so no other file in either algorithm's call graph needed
modification — same integration shape Falcon's existing
`optimized/falcon512/{shake.c,vrfy.c}` already established.

### ML-DSA (all 3 variants: 44/65/87)

- **NTT/iNTT** (`ntt.c`): `ntt()`/`invntt_tomont()` now dispatch to
  `ntt_engine.sv` using the twiddle tables derived and RTL-verified
  bit-exact against the real reference (see the "Phase 3 prep" section
  above) — `gm[]` is `zetas[]` directly, `igm[]` is `zetas[]` under a
  bit-permutation local to each power-of-two stage block. `NTT_CTRL.NOSCALE`
  selects ML-DSA's no-per-stage-scaling inverse convention; the single
  combined `f`-multiply correction stays in software exactly as the
  original does.
- **Matrix-A expansion** (`poly.c`'s `poly_uniform()`, called
  `polyvec_matrix_expand()`, K×L times per verify): replaced with a single
  `rej_sampler.sv` job per call (`REJ_CTRL.CAND3/RATE168/OUTWIDE`, 34-byte
  seed = 32-byte ρ + 2-byte little-endian nonce, matching
  `dilithium_shake128_stream_init()`'s own absorb exactly) — the sampler's
  own FSM autonomously re-permutes and continues squeezing across as many
  SHAKE128-rate blocks as needed, the same "one HW job replaces the whole
  squeeze-and-reject loop" shape as Falcon's existing
  `Zf(hash_to_point_hw)()`.
- **Left software** (scope boundary, not an oversight): the 2-3 SHAKE256
  calls per verify (public-key hash for μ, the transcript hash, and the
  challenge-polynomial expansion) — small relative to matrix-A expansion
  and the NTTs, the two dominant costs.

| Variant | Baseline cycles | Optimized cycles | Speedup | Baseline instr | Optimized instr | Result |
| --- | ---: | ---: | ---: | ---: | ---: | :---: |
| ML-DSA-44 | 1,504,523 | 896,175 | 1.68× | 1,296,187 | 567,654 | `*** SUCCESS ***`, KAT-correct |
| ML-DSA-65 | 2,413,716 | 1,346,166 | 1.79× | 2,100,021 | 855,346 | `*** SUCCESS ***`, KAT-correct |
| ML-DSA-87 | 3,941,622 | 2,043,509 | 1.93× | 3,459,121 | 1,313,665 | `*** SUCCESS ***`, KAT-correct |

### SPHINCS+ / SLH-DSA (all 6 variants: 128f/192f/256f × robust/simple)

- **`thash()`** (`thash_shake_{robust,simple}.c`): `inblocks∈{1,2}` (F/H,
  the overwhelming majority of calls — FORS sk-to-leaf, FORS/WOTS+ Merkle
  root climbs) dispatch to `chain_job_ctrl.sv` (`CA_OP_THASH1`/
  `CA_OP_THASH2`). `inblocks>2` (FORS's final root-aggregation hash and
  WOTS+'s leaf hash — 23 calls total per verify) stay in software:
  `chain_job_ctrl.sv`'s `CHAIN_IO`/`CHAIN_IN2` registers only hold one or
  two `SPX_N`-byte blocks, matching the FIPS 205 F/H primitives exactly,
  not the generalized variable-length T_l construction those two call
  sites need.
- **`gen_chain()`** (`wots.c`, WOTS+ chain-stepping, the dominant verify
  cost — up to `SPX_WOTS_W-1` sequential steps × `SPX_WOTS_LEN` chains ×
  `SPX_D` layers): replaced entirely with **one** `chain_job_ctrl` job per
  chain, using `CHAIN_CTRL.STEPS>1` — the FSM internally loops
  `step_cnt = start..start+steps-1`, feeding each step's digest back as the
  next step's input and overlaying `step_cnt` into ADRS byte 31 every step,
  avoiding per-step MMIO/dispatch overhead on top of the arithmetic saving.
- `spx_thash_robust` (defined `1`/`0` by whichever of
  `thash_shake_robust.c`/`thash_shake_simple.c` is linked, declared in
  `thash.h`) lets the shared `wots.c` (byte-identical across all 6
  variants, confirmed via diff before copying) select the correct
  `CHAIN_CTRL.ROBUST` bit without itself differing between variants.
- Both call-site changes were validated standalone first
  (`tests/app-tests/{thash,thash2,thash-wots}`, Phase 0) before being wired
  into real algorithm code here.

| Variant | Optimized cycles | Optimized instr | Result |
| --- | ---: | ---: | :---: |
| SPHINCS-128f-robust | 2,227,893 | 1,744,078 | `*** SUCCESS ***`, KAT-correct |
| SPHINCS-128f-simple | 1,164,835 | 884,034 | `*** SUCCESS ***`, KAT-correct |
| SPHINCS-192f-robust | 3,915,071 | 3,157,426 | `*** SUCCESS ***`, KAT-correct |
| SPHINCS-192f-simple | 2,051,594 | 1,615,666 | `*** SUCCESS ***`, KAT-correct |
| SPHINCS-256f-robust | 4,940,704 | 4,122,786 | `*** SUCCESS ***`, KAT-correct |
| SPHINCS-256f-simple | 2,550,913 | 2,051,035 | `*** SUCCESS ***`, KAT-correct |

**SPHINCS+ baseline (software-only) cycle counts were not collected this
session** and are reported as such rather than estimated: cycle-accurate
Verilator simulation of unaccelerated SPHINCS+ verify is extremely slow
(hours-scale per KAT — an untracked baseline run for `SPHINCS-128f-robust`
launched earlier in this session had not produced a result after 2+ hours
of CPU time before being superseded). The `simple`-vs-`robust` cycle-count
ratio within each security level (roughly 1.9×, matching `robust`'s extra
per-`thash()`-call bitmask-generation SHAKE256 hash) is consistent across
128f/192f/256f, which is the expected structural signature of the
construction difference and a useful internal sanity check in the absence
of a measured software baseline.

### Not yet accelerated (explicit scope boundary for this pass)

- ML-DSA's 2-3 SHAKE256 message-hash/challenge calls per verify.
- SPHINCS+'s 23 multi-block (`inblocks>2`) `thash()` calls per verify
  (FORS root aggregation, WOTS+ leaf hash) — would need
  `chain_job_ctrl.sv`'s register interface generalized beyond 1-2 blocks,
  or a fallback through the general-purpose `keccak_dma_ctrl.sv` absorb
  path instead.

Both are comparatively small contributors next to matrix-A expansion/NTT
(ML-DSA) and WOTS+ chain-stepping (SPHINCS+), the two costs this pass
targeted.

## 2026-08-09 — Phase 4: SHAKE message-hash and multi-block thash() offload

Closes the two gaps explicitly flagged at the end of Phase 3: ML-DSA's
SHAKE256 message-hash/challenge calls, and SPHINCS+'s multi-block
(`inblocks>2`) `thash()` calls (FORS's root-aggregation hash, WOTS+'s leaf
hash) that didn't fit `chain_job_ctrl.sv`'s fixed 1-2-block register
interface.

**Integration point, simpler than Phase 3 anticipated**: every
`shake128_*`/`shake256_*`/`sha3_*` function in a given `fips202.c` routes
through exactly one function, `KeccakF1600_StatePermute()`, for the actual
24-round permutation -- the byte-level absorb/pad/squeeze bookkeeping around
it is comparatively cheap. Replacing *only that one function's body* with a
dispatch to the shared vrf_ip Keccak core (the same CSREG/DATA[]
raw-permute MMIO interface already used throughout this accelerator: upload
25 words, pulse `CSREG.START`, wait `CSREG.DONE`, download the result)
accelerates every caller in the file with no other call site needing to
change. No RTL modification was required -- `keccak_dma_ctrl.sv`'s
general-purpose absorb engine was considered but turned out to be
unnecessary; the raw-permute path alone was sufficient and is simpler.

For ML-DSA this newly covers the μ/transcript/challenge SHAKE256 calls in
`sign.c`/`poly.c` left software-only in Phase 3. For SPHINCS+ this covers
`hash_message()` (verify's message digest, never previously offloaded) and
the `inblocks>2` fallback path inside `thash()` (previously left in
software as a stated Phase 3 scope boundary) -- both without touching
`thash_shake_{robust,simple}.c` at all, since they call `shake256()` from
`fips202.c` for that fallback.

ML-DSA verify's Keccak usage is fully sequential (each incremental context
runs to completion before the next starts, unlike Falcon's KeyGen/Sign/
Verify which interleaves many concurrent SHAKE256 contexts), so no
residency tracking was needed -- every `KeccakF1600_StatePermute()` call is
a self-contained upload-permute-download round trip.

| Variant | Phase 3 cycles | Phase 4 cycles | Reduction | Cumulative vs. SW baseline |
| --- | ---: | ---: | ---: | ---: |
| ML-DSA-44 | 896,175 | 818,613 | 8.7% | 1.84× (baseline 1,504,523) |
| ML-DSA-65 | 1,346,166 | 1,226,830 | 8.9% | 1.97× (baseline 2,413,716) |
| ML-DSA-87 | 2,043,509 | 1,909,871 | 6.5% | 2.06× (baseline 3,941,622) |
| SPHINCS-128f-robust | 2,227,893 | 1,181,051 | 47.0% | n/a (SW baseline not collected) |
| SPHINCS-128f-simple | 1,164,835 | 625,755 | 46.3% | n/a |
| SPHINCS-192f-robust | 3,915,071 | 1,934,901 | 50.6% | n/a |
| SPHINCS-192f-simple | 2,051,594 | 1,011,534 | 50.7% | n/a |
| SPHINCS-256f-robust | 4,940,704 | 2,326,409 | 52.9% | n/a |
| SPHINCS-256f-simple | 2,550,913 | 1,184,582 | 53.6% | n/a |

All 9 variants `*** SUCCESS ***`, KAT-correct, on real RTL simulation.

**Notable asymmetry**: SPHINCS+'s reduction (~46-54%) is far larger than
ML-DSA's (~7-9%). This makes sense in hindsight -- ML-DSA's SHAKE256 usage
is a handful of small, fixed-size calls (mu/transcript/challenge), a minor
fraction of a verify already dominated by NTT/matrix-A-expansion HW work,
whereas SPHINCS+'s multi-block `thash()` fallback was, before this pass,
the *only* unaccelerated hashing left in a verify otherwise fully offloaded
via `chain_job_ctrl` (the 22 WOTS+ leaf hashes and 1 FORS root-aggregation
hash, each `inblocks*SPX_N` bytes, apparently cost as much or more in pure
software as the thousands of now-HW-accelerated WOTS+ chain steps combined)
-- confirming this was a materially larger contributor than either the
Phase 3 scope note or an a-priori guess would have suggested.

### Scope now fully closed for this pass

With both Phase 3 and Phase 4 complete, every hash/NTT/rejection-sampling
primitive reached by `crypto_sign_open`/`crypto_sign_verify` across all 11
schemes is hardware-offloaded. No further known gaps remain in the current
`vrf_ip` verify-acceleration scope.
