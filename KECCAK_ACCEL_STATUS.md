# HAWK Keccak Accelerator — Session Summary (2026-07-15/16)

## Context

`HAWK/cva6` (branch `HAWK`) runs the HAWK post-quantum signature scheme
(HAWK-256/512/1024, pure C, in `tests/hawk-*`) on the CVA6 RISC-V core, and is
mid-refactor of a custom Keccak/SHA3 hardware accelerator meant to speed up
the SHAKE calls that dominate KeyGen/Sign cycles.

Two generations exist in the working tree (uncommitted, on top of commit
`f3c80e1ba`):

- **Gen 1 (removed this round):** a CVXIF custom-instruction coprocessor
  (`keccak_xif`, `rxri.l/h` instructions).
- **Gen 2 (current):** a memory-mapped AXI peripheral
  (`keccak_ip/rtl/keccak_axi_top.sv`, `keccak_dma_ctrl.sv`), register
  interface generated via reggen from `keccak_ip/keccak.hjson`. Wired in as
  AXI slave `Keccak` at `0x5000_0000`, with its own DMA-master path back into
  the crossbar so it can absorb/squeeze directly from CVA6 memory.

Entering this session, Gen 2's software driver (`tests/hawk-256-keccak/sha3.c`)
implemented single-slot hardware state residency (`hw_owner` pointer +
per-context `hw_seen` flag) on top of a DMA job engine that can
autonomously chain the permutation across multiple absorbed rate blocks
within one job descriptor. The full HAWK-256 KAT (`tests/hawk-256-keccak/main.c`)
had never actually been run against this Gen-2 RTL.

## Task 1: rebuild + run, find the "SK mismatch"

First full run of the real KAT surfaced `ERROR: SK mismatch` after KeyGen
(~8.78M cycles). Register-level tests that already existed
(`keccak_dma_absorb_test.c`, `keccak_interleave_test.c`) all passed, so the
bug had to be in a code path none of them exercised.

**Bisection method:** enabled `-DHAWK_DEBUG=1` (existing but previously
unused debug-print infrastructure in `hawk_inner.h`) on both the
known-correct pure-software build (`tests/hawk-256`) and the Gen-2 build
(`tests/hawk-256-keccak`), and diffed every printed intermediate KeyGen value
(`f, g, F, G, q00, q01, q11, priv, pub`). Everything matched *except* the
last 16 bytes of `priv` — the SHAKE256 hash of the 450-byte public key
(`encode_private()`'s `hpub`). This is the **first point in the entire
KeyGen call tree where an absorb spans more than one 136-byte SHAKE256 rate
block** (450 = 3×136 + 42); every earlier SHAKE call in KeyGen absorbs well
under one rate block.

### Bug #1 (RTL): stale `CSREG.DONE`

Reproduced cheaply with a dedicated register-level test
(`tests/keccak64/keccak_dma_chain_bisect_test.c`, ~13K cycles instead of
~10M) that bisected the exact trigger: **2 or more internally-chained
permutations within a single DMA absorb job**, followed by a
CSREG-triggered squeeze permutation.

Root cause, confirmed via VCD waveform trace
(`TRACE_FAST=1`, parsed as text): in `keccak_ip/rtl/keccak_axi_top.sv`,

```systemverilog
assign ip_to_reg_file.csreg.done.d  = keccak_done;
assign ip_to_reg_file.csreg.done.de = keccak_done;
```

`keccak_done` pulses for **any** permutation completion — whether
triggered by software via `CSREG.START` or internally by the DMA job
engine chaining across rate blocks. Any absorb crossing ≥1 rate block
boundary leaves `CSREG.DONE` latched at 1 (nothing else ever clears it),
so the *next* genuine CSREG-triggered squeeze permutation's software poll
(`process_block_resident()`'s `while (!(*csreg & DONE));`) sees the stale
bit and returns immediately — before the real permutation has actually
finished — and the subsequent state readback captures a mid-round,
garbage state.

**Fix:** added a `csreg_perm_pending` flop, set on the CSREG-start rising
edge and cleared on `keccak_done`, and gated `csreg.done.de` on it so only
a permutation genuinely triggered via `CSREG.START` can set `csreg.done`.
This alone fixed KeyGen.

### Bug #2 (software): `shake_context` clone vs. hardware residency

With KeyGen fixed, the KAT progressed further and failed with
`ERROR: SM mismatch` during Sign. Same bisection method (HAWK_DEBUG diff
against pure-software) localized the divergence to the very first
Gaussian sample (`dx0`/`dx1`) computed by `sig_gauss()`.

`hawk_sign.c`'s `sig_gauss()` (non-AVX2 path, the one actually compiled
here) does, once per lane in a 4-iteration loop:

```c
shake_context sc;
if (sc_extra != NULL) {
    sc = *sc_extra;          /* plain struct copy */
}
...
shake_inject(&sc, seed, 41);
```

Two compounding problems:

1. `shake_inject()` never writes absorbed bytes back into `sc->A[]` in
   RAM — only the accelerator's `DATA[]` registers hold them until an
   eviction happens. If `sc_extra` is *currently* the hardware-resident
   context, a plain struct copy silently captures whatever stale value
   `sc_extra->A[]` had in RAM (e.g. all zeros from the last
   `shake_init()`), dropping everything actually absorbed.
2. The copy also carries over `hw_seen = 1`. Combined with `sc` being a
   **stack-local reused at the same address on every loop iteration**,
   a stale `hw_owner` pointer left dangling from the *previous*
   iteration's `sc` makes `keccak_hw_prepare_for_absorb()`'s
   pointer-identity fast path (`hw_owner == sc && sc->hw_seen`) wrongly
   believe this iteration's `sc` is already the resident context —
   skipping the upload of the (correct) cloned data entirely and
   silently absorbing into whatever the *previous* iteration's hardware
   state happened to be.

**Fix:** added `shake_clone(dst, src)` to `sha3.c`/`sha3.h`:
- if `src` is currently hardware-resident, sync it back to RAM first
  (without relinquishing its residency), so the struct copy is accurate;
- if `hw_owner` currently (and staleley) equals `dst`'s address, clear
  it, forcing an honest re-upload on `dst`'s first subsequent use.

Applied at all 4 struct-copy call sites: `hawk_sign.c:720,860,1622`,
`hawk_vrfy.c:3013`. Replicated identically into `tests/hawk-512-keccak/`
and `tests/hawk-1024-keccak/` (byte-identical `sha3.c`/`hawk_sign.c`/
`hawk_vrfy.c` across all three variants) — those have received the same
source fix but have **not** been run through their own full KAT yet.

## Result: full HAWK-256 KAT passes

```
Keygen OK
Sign OK
Verify OK
```
10,301,440 total cycles (KeyGen 8,760,301 / Sign 486,156 / Verify 554,652).
First fully-correct real-RTL-simulated run of HAWK-256 on the Gen-2
accelerator.

## Task 2: DMA-absorb vs. permutation-only cycle comparison

Built a second `shake_init/inject/flip/extract` implementation,
`tests/hawk-256-keccak/sha3_permonly.c`: absorb/squeeze bookkeeping
(byte-XOR into state, rate-block boundary detection, padding) all in plain
C exactly like the pure-software baseline, with the accelerator used
*only* as a one-shot 24-round permutation function (upload 25 words via
`CSREG`, poll, read 25 words back) — no DMA job engine, no residency
tracking, no `hw_owner`/`hw_seen` at all.

| Phase | Pure software | Permutation-only (this session) | Full DMA-absorb (Gen-2) |
|---|---:|---:|---:|
| KeyGen | 9,948,715 | 8,798,037 | 8,760,301 |
| Sign | 849,512 | 494,313 | 486,156 |
| Verify | 606,729 | 561,971 | 554,652 |
| **Total** | **11,404,956** | **9,854,321** | **9,801,109** |

**Key finding: the DMA-absorb engine's entire job-engine/residency
complexity — the thing both bugs above lived in — buys under 1% over the
much simpler permutation-only design** (0.4–1.7% per phase). Essentially
all of the speedup over pure software comes from offloading the
permutation itself; *how* the input bytes get into the accelerator barely
matters, because SHAKE256's 136-byte rate block is cheap for the CPU to
XOR locally compared to the fixed cost of invoking the permutation (bus
round-trip + round computation).

### Single-call cost breakdown

To separate "fixed per-call overhead" from "24-round compute time",
measured one isolated CSREG permutation call via
`tests/keccak64/keccak_single_call_cost.c` (mcycle around each phase):

| Phase | Cycles | Share |
|---|---:|---:|
| Upload (25 stores) | 224 | 36% |
| Start + poll (compute + handshake, includes all 24 rounds) | 70 | 11% |
| Readback (25 loads) | 282 | 46% |
| **Full round trip** | **616** | 100% |

**This is decisive: data movement (upload + readback, 506 cycles) is ~82%
of the per-call cost; the 24-round permutation plus its handshake is only
~70 cycles (~11%).** ~9 cycles/store, ~11.3 cycles/load — consistent with
AXI crossbar round-trip latency per individual register transaction, not
with compute time. Even a hypothetical *zero-cycle* permutation would only
remove ~11% of the per-call cost. **Optimizing the load/store path
dominates any plausible gain from round-unrolling and carries none of its
fmax risk.**

## Where the effort actually is (as of this writing)

`keccak_ip/rtl/keccak_dp.sv` / `keccak_cu.sv`: the permutation core does
**1 round per cycle, 24 cycles per call**, driven by a simple FSM
(`counter_nr_rounds` 0→23). This is the same regardless of which absorb
strategy (DMA vs. permutation-only) is used, and is the shared bottleneck.

Given the single-call breakdown above, **the data-loading/state-storage
path is the clear priority**, not round unrolling:

1. **Optimize the data-loading/state-storage path (priority).** 506 of
   616 cycles (82%) is upload+readback of 25 separate one-word AXI
   transactions. Candidate levers, roughly in order of expected
   impact-to-effort:
   - **Don't round-trip the capacity (words 17–24) on every call.**
     A sponge's capacity is never touched by absorption and never
     externally read during squeeze; if hardware simply keeps the *full*
     1600-bit state resident across back-to-back calls (a much lighter
     residency model than the current DMA job engine — no multi-context
     tracking, no job descriptors, just "don't clobber what's already
     there"), software only ever needs to write/read the 17 rate words.
     That alone cuts transaction count ~32%, worth roughly 224×8/25 ≈ 72
     upload cycles + 282×8/25 ≈ 90 readback cycles ≈ **160 of 616 cycles
     (~26%)**, before touching anything else.
   - **Skip the readback entirely when the caller doesn't need it**
     (e.g. mid-absorb calls that only feed more input forward) — right
     now every call pays the full 282-cycle readback even when nothing
     downstream reads `A[]` before the next call.
   - **Burst instead of 25 discrete transactions.** ~9–11 cycles per
     word strongly suggests AXI crossbar round-trip/arbitration latency
     dominates, not raw bandwidth — a single burst (AXI INCR) transfer
     of the needed words could amortize that latency across the whole
     transfer instead of paying it 17–25 times. Requires the register
     slave (or a dedicated fast-path window) to support burst addressing;
     bigger lift than the two options above but the largest single win.
2. **Unroll the round function** (e.g. 2 rounds/cycle → 12-cycle
   permutation instead of 24), following the pattern seen in
   `tches2026_3-paper76-supplementary_material/rtl/my_shake256/keccak_statepermute_shake256.sv`'s
   `round_2stage`. Now clearly secondary: the entire 24-round compute is
   only ~11% of one call's cost, so even halving it caps out around ~5–6%
   overall — and it carries real fmax risk (doubling combinational depth
   per cycle) that the data-path options above don't.

## Files touched this session

**RTL fix:**
- `keccak_ip/rtl/keccak_axi_top.sv` — `csreg_perm_pending` gating fix.

**Software fixes (identical across all three):**
- `tests/hawk-256-keccak/sha3.c`, `hawk_sign.c`, `hawk_vrfy.c`
- `tests/hawk-512-keccak/sha3.c`, `hawk_sign.c`, `hawk_vrfy.c`
- `tests/hawk-1024-keccak/sha3.c`, `hawk_sign.c`, `hawk_vrfy.c`

**New permutation-only variant:**
- `tests/hawk-256-keccak/sha3_permonly.c`

**New regression/debug tests (`tests/keccak64/`), not yet cleaned up:**
- `keccak_dma_chain_bisect_test.c` — 1/2/3-internally-chained-permutation
  absorb regression (the fast repro for bug #1).
- `keccak_dma_2chain_trace.c`, `keccak_dma_3chain_isolated.c`,
  `keccak_dma_3chain_preperm_check.c` — narrower single-case repros used
  during bisection, largely superseded by the bisect test above.
- `keccak_single_call_cost.c` — single-permutation-call cost breakdown.

**New test in `tests/hawk-256-keccak/`:**
- `keccak_squeeze_multiblock_test.c` — multi-rate-block squeeze
  correctness test (closed a real gap: nothing previously squeezed more
  than one rate block through the real driver).

## Outstanding / not yet done

- Nothing from this session is committed (still on top of `f3c80e1ba`).
- hawk-512-keccak / hawk-1024-keccak have the same source fixes applied
  but have not been run through their own full KAT.
- The throwaway debug test files under `tests/keccak64/` should probably
  be pruned or consolidated before committing.
- Next optimization phase (round unrolling vs. data-path optimization)
  not yet started — this file is the handoff point for that work.
