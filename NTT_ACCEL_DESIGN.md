# NTT/Montgomery-multiply accelerator — design scope (2026-07-21, updated 2026-07-22)

## Status

**Implemented and integrated.** `vrf_ip/rtl/ntt_engine.sv`, the
`NTT_*` register additions to `vrf_ip/vrf.hjson`, and the
`vrf_axi_top.sv` wiring all exist and have been confirmed correct
end-to-end on real verilator/DV simulation, not just compiled.

The engine implements a generic 32-bit-domain Montgomery NTT/iNTT:
`NTT_P_VAL`/`NTT_P0I_VAL` are plain per-job registers (any prime, not
hardcoded — see "Widened prime support" below), and `NTT_CTRL.MODE`
selects direction only (forward/inverse). Falcon Verify's
`mq_NTT_hw()`/`mq_iNTT_hw()` (`tests/falcon512-opt/vrfy.c`,
`tests/falcon1024-opt/vrfy.c`) dispatch to this same engine for its
single prime `q=12289`.

## Widened prime support

The original design (register map and RTL both) hardcoded exactly two
primes behind a 1-bit prime-select register. This was too narrow for
general use: only whichever two primes happened to be hardcoded could
ever reach hardware.

**Change:** the 1-bit prime-select register (2 hardcoded prime/p0i pairs
as RTL `localparam`s) was replaced with `NTT_P_VAL`/`NTT_P0I_VAL` (two
32-bit registers, software supplies both directly). Inside
`ntt_engine.sv`, this removed the prime-select mux entirely and replaced
it with a straight `p_q`/`p0i_q` register pair latched at job start — the
Montgomery multiply-reduce datapath already treated `p`/`p0i` as plain
inputs throughout (per-butterfly `mp_montymul`/`mp_add`/`mp_sub`/
`mp_half` never referenced a specific prime value), so **this was a net
reduction in RTL**, not an addition: two hardcoded 32-bit constants and a
mux disappear, replaced by two register fields the reg-file
infrastructure already provides for free. No FSM, batching, or
address-generator logic changed at all.

This generalization is what lets Falcon Verify's `mq_NTT_hw()`/
`mq_iNTT_hw()` reuse the same engine for `q=12289` — a prime never
hardcoded into the original design — without any RTL change (see
`vrfy.c`'s hardware-offload comment). The only guard left is a size
threshold, `NTT_HW_MIN_LOGN = 2` (`logn<2` stays in software): below that,
the fixed per-job overhead (5 register writes, the DONE poll, the
scratch-window copy) isn't worth it — `logn==0` is already a no-op in
`mp_NTT`/`mp_iNTT` themselves, and `logn==1` is a single butterfly. This
threshold is a judgment call, not derived from profiling; worth revisiting
if a future profile shows it's miscalibrated.

The widened registers were tested against several distinct primes (not
just the originally hardcoded two), confirming the design works for
genuinely arbitrary primes rather than continuing to pass by
coincidence -- confirmed: all 16 cases (2 logn sizes x 4 primes x 2
directions) pass with 0 mismatches on real RTL simulation.

## Single-operation golden-model benchmarks

A software-vs-hardware single-operation benchmark (calling the software
NTT/iNTT directly, bypassing the hardware dispatcher, versus dispatching
to hardware; both cycle-counted via the `mcycle` CSR in isolation, no
KAT or other traffic) used n=256. Correctness is a self-contained
round-trip check (`mp_iNTT(mp_NTT(x)) == x`, exact — no external
expected-vector constants needed since `mp_iNTT`'s `n^-1` scaling is
built into every stage).

| Operation | Software | Hardware | Speedup |
|---|---:|---:|---:|
| NTT (n=256) | 35,255 cycles | 28,574 cycles | 1.23x |
| iNTT (n=256) | 42,176 cycles | 28,563 cycles | 1.48x |

**Hardware cost breakdown for one NTT call:**

| Phase | Cycles | Share |
|---|---:|---:|
| scratch-copy-in (256 stores) | 1,439 | 5% |
| **regs+GO+poll (hardware compute+handshake)** | **24,706** | **87%** |
| scratch-copy-out (256 loads) | 2,214 | 8% |
| **Total** | 28,487 | (≈ full-round-trip number above, small measurement-boundary difference) |

**This overturned the working assumption that fixed per-call overhead**
(register writes, scratch-window copy) **was the dominant cost holding
back the win.** It is not — it's a modest 13%. The 87% "regs+GO+poll"
bucket is the accelerator's *own* internal per-butterfly cost: 1024
butterflies for n=256 (`n/2 * logn`), 24,706 cycles / 1024 ≈ 24.1
cycles/butterfly — far above the ~6-cycle compute estimate (4-cycle
`MM_STEP` + 2-cycle `STORE_K1`/`STORE_K2`), confirming the "no AXI burst
capability" caveat (see "Batched twiddle reuse" below) is the actual
bottleneck in practice, not just a theoretical concern: every one of the
5 words per butterfly (3 loads, 2 writebacks) pays a full single-beat
req/gnt/valid round trip inside `ntt_engine.sv`'s FSM, with no way to
pipeline or coalesce them.

**Why software is competitive despite the "hardware accelerator"
label:** a 256-entry `a[]` array (256×4 = 1KB) comfortably fits in a
typical L1 D$, so a CPU's own scalar NTT loop benefits from cache
locality on repeated access to the same small array across all `logn`
stages. `ntt_engine.sv`, as a separate AXI master with no cache of its
own, pays full DRAM latency on every single word, every time, with no
such benefit. This is the real explanation for the modest 1.2-1.5x
single-operation speedup.

## Batched twiddle reuse and the abandoned burst-DMA attempt ("#1", 2026-07-23)

The single-operation benchmarks above pinned the bottleneck to per-word
DRAM round-trip latency inside `ntt_engine.sv`'s FSM (87% of a single
NTT call), not setup overhead. Two attacks on that were scoped: batching
twiddle fetches (cheap, no protocol changes) and a real AXI burst DMA
path (bigger win in principle, more RTL/risk). Both were attempted;
only the first survived.

**What shipped — batched twiddle reuse.** `ntt_engine.sv` now batches up
to 16 consecutive `v`'s for a single `u` (not spanning twiddle groups)
into one in-flight group, fetching the shared twiddle value once per
batch instead of once per butterfly — up to 16x fewer twiddle round
trips per stage. `a[]` loads/stores are still single-outstanding,
single-word DRAM transactions (unchanged from the original design);
only the twiddle fetch is amortized. Compute operates directly on
dedicated `k1_batch_q`/`k2_batch_q` registers, which also let the FSM
drop the read-modify-write scatter/gather dance the original design
needed to stage words through the shared Keccak state array — a net
reduction in FSM states and register bits, not an addition, despite the
batch registers.

**What was attempted and abandoned — a real 16-word AXI burst.** The
idea: widen `ntt_engine.sv`'s memory port to 16 lanes and issue one
`CACHE_LINE_REQ` burst per batch instead of 16 sequential single-beat
transactions, cutting round-trip count (not just per-word FSM overhead)
directly. Implementation reused `axi_adapter.sv` (`corev_apu/tb/
ariane_testharness.sv`'s `i_keccak_dma_axi_master` instance) rather than
building a dedicated burst master, on the reasoning that `type_i` is a
per-transaction input (not a fixed parameter), so the same adapter
instance could serve both burst and the existing single-beat traffic
from `keccak_dma_ctrl.sv`.

This got as far as full RTL integration and a dedicated fast-turnaround
smoke test (`ntt_burst_smoke_test.c`, logn=5 — small enough to iterate
in ~3 minutes instead of the full suite's ~50), and along the way
surfaced two real, fixable bugs on real RTL simulation (not caught by
static review): a lane-index bug in the 16-lane load/writeback loops
(`mem_rdata_i[i]`/`mem_wdata_o[i]` needed to be `[i>>1]`, since two
32-bit words pack into each 64-bit AXI lane), and a `size_i` mismatch
against `axi2mem.sv` (the testbench's AXI-to-SRAM memory model), whose
address-stepping logic ignores the declared `SIZE` field entirely and
always advances 8 bytes/beat regardless.

Fixing both still left every burst-mode test case failing. The actual
root cause, found by reading `axi_adapter.sv`'s read-address generation
directly: for any non-`SINGLE_REQ` (i.e. burst) request, it unconditionally
zeroes the low `CACHELINE_BYTE_OFFSET` (default 8) address bits —

```systemverilog
if (!CRITICAL_WORD_FIRST && type_i != ariane_pkg::SINGLE_REQ) begin
  axi_req_o.ar.addr[CACHELINE_BYTE_OFFSET-1:0] = '0;
end
```

— because it was built for CVA6's own dcache/icache cache-line misses,
where a "cache line" fetch is always meant to snap to its natural
256-byte-aligned boundary. Our batch base addresses (`k1_base`/`k2_base`)
are arbitrary word offsets with no such alignment guarantee; in the
logn=5 smoke test, `k2_base_byte_addr` (offset 64 bytes into the array)
got silently truncated back to offset 0, so the k2 burst read actually
re-fetched k1's data, corrupting every butterfly in the batch. This is a
protocol/architecture mismatch, not a bug in our RTL that a fix could
patch — `axi_adapter.sv`'s burst path is tied to fixed-alignment
cache-line semantics, not general arbitrary-address block transfers.

**Decision: abandoned, not reworked.** Fixing this properly would mean
either (a) constraining the batching scheme so every burst's base address
lands on a 128/256-byte boundary — a real redesign with an unknown hit
rate against the actual batching pattern, likely eroding much of the
expected win — or (b) building a genuinely dedicated burst master that
generates its own unmasked AR addresses, bypassing `axi_adapter.sv`
entirely — real new RTL and verification surface, the option originally
passed over specifically because reusing `axi_adapter.sv` looked cheaper.
Given the explicit "lowest hardware possible" priority and that this is
the second cost/risk underestimate found for this path (the first being
the `DATA_WIDTH`-fixes-burst-length issue that motivated the
`axi_adapter.sv`-reuse choice in the first place), burst DMA was dropped.
All burst-specific RTL (`mem_burst_o`, the 16-lane port widening, the
`is_burst_q` branches) and the burst smoke test were removed; the
batched-twiddle-reuse structure was kept since it stands on its own
merit and needed no burst-related changes to work.

## Why

`mp_NTT`/`mp_iNTT`/`mp_montymul` are the three core arithmetic
primitives behind number-theoretic-transform-based lattice cryptography.
Rather than building bespoke hardware for one specific caller, the
highest-leverage target is to hardware-accelerate these shared
primitives directly, so any caller built against the same
Montgomery-domain NTT/iNTT shape benefits automatically — the same way
every `shake_*` call already gets transparently redirected to the
Keccak AXI peripheral without each caller needing per-call-site
awareness. Falcon Verify's `mq_NTT_hw()`/`mq_iNTT_hw()` (`vrfy.c`) are
exactly this: a drop-in dispatcher to the same engine, for a different
prime (`q=12289`) than originally targeted.

## What the reference design does (and why we don't copy it wholesale)

`tches2026_3-paper76-supplementary_material/rtl/bfu/` is a complete
standalone ASIC arithmetic engine for NTT-based lattice cryptography —
no host CPU, no DRAM:

- `buffer.sv`: 4-bank dual-port BRAM scratchpad, `BRAM_DEPTH(512) ×
  VEC_BITS(128) × 4 banks` ≈ **32 KB on-chip**, holding every polynomial
  the whole computation ever touches (see the `ADDR_*` map in
  `defines.v`).
- `bfu_datapath.sv`: 4 parallel `re_bfu` cores, each consuming 4×32-bit
  words/cycle → 16 coefficients/cycle, `BFU_PIPE_STAGES=7` deep, plus a
  twiddle ROM (`tw_rom.sv`), permutation networks, pre/post-shifters.
- `re_bfu.sv` (1158 lines): the actual per-lane kernel — a pipelined
  32×32 Montgomery multiplier (`bfu_block1-4`, `mred`) + modular
  add/sub-with-reduce (`addred32`/`subred32`, and 16-bit variants for a
  second, smaller modulus).
- `msum4.sv`: a streaming Montgomery multiply-accumulate over two primes
  at once.

None of the 32 KB buffer or the 16-wide parallelism fits our situation:
CVA6's DRAM already holds every polynomial, and our actual NTT-domain
workload is nowhere near needing 16-wide sustained throughput.
Duplicating that scale would be pure waste. What *is* worth borrowing is
the per-lane arithmetic kernel shape (`re_bfu`'s Montgomery
multiply/reduce + modular add/sub), scaled down to one lane.

## The actual C algorithm being targeted

The algorithm being hardware-accelerated is a textbook iterative
decimation-in-time NTT (non-AVX2 path):

```c
size_t t = (size_t)1 << logn;
for (unsigned lm = 0; lm < logn; lm++) {
    size_t m = (size_t)1 << lm;
    size_t ht = t >> 1;
    size_t v0 = 0;
    for (size_t u = 0; u < m; u++) {
        uint32_t s = gm[u + m];                 /* twiddle factor */
        for (size_t v = 0; v < ht; v++) {
            size_t k1 = v0 + v, k2 = k1 + ht;
            uint32_t x1 = a[k1];
            uint32_t x2 = mp_montymul(a[k2], s, p, p0i);
            a[k1] = mp_add(x1, x2, p);
            a[k2] = mp_sub(x1, x2, p);
        }
        v0 += t;
    }
    t = ht;
}
```

The inverse transform is the mirror-image (decimation-in-frequency, same
butterfly shape). `mp_montymul` is standard word-level Montgomery
reduction, R=2^32:

```c
uint64_t z = (uint64_t)a * (uint64_t)b;
uint32_t w = (uint32_t)z * p0i;
uint32_t d = (uint32_t)((z + (uint64_t)w * (uint64_t)p) >> 32) - p;
return d + (p & tbmask(d));   /* conditional add-back */
```

`mp_add`/`mp_sub` are a 32-bit add/sub plus one conditional add-back —
essentially free in hardware (single cycle, no multiplier involved).

`p`/`p0i` are plain per-job inputs (see "Widened prime support" above),
so this same loop shape and reduction serve any modulus a caller
supplies, including Falcon Verify's `q=12289`.

One nuance worth calling out: CVA6 already has a hardware 64-bit
multiplier (RV64IM `mul`/`mulhu`), so `mp_montymul`'s two 32×32
multiplies are *not* the dominant cost in software — the loop/branch
overhead, function-call boundary (if not inlined), and scalar
load/store traffic through `a[k1]`/`a[k2]` per butterfly are. So the
hardware win here comes mainly from (a) collapsing that per-butterfly
overhead into a dedicated FSM + pipelined datapath, and (b) moving
operand traffic onto burst AXI instead of scalar loads/stores — not
from "multiplying faster than CVA6 already can."

## Proposed unit: `ntt_engine`

### Storage — no new buffer, reuse Keccak's existing state array, batched

Exactly like `keccak_dma_ctrl.sv` already does: operands and twiddle
factors stream to/from CVA6 DRAM over the accelerator's existing AXI
master. No new on-chip buffer or ROM.

- **Twiddle tables** (`gm[]`/`igm[]`): software already builds these via
  `mp_mkgm`/`mp_mkigm` — no hardware table-generation needed at all,
  just point the engine at the existing DRAM array.
- **Batched operand/twiddle staging (the actual point of reusing a
  1600-bit register file)**: the first version of this design staged
  one butterfly (twiddle + `a[k1]` + `a[k2]` = 3×32-bit words = 96 bits)
  at a time — under 6% of the 1600-bit state array. Instead, the
  engine stages a **batch of up to 16 independent `(twiddle, x1, x2)`
  triples** — 48 of the available 50 32-bit words in the 25×64-bit
  Keccak state array — computed in place (results overwrite `x1`/`x2`,
  no separate output storage needed), and drained one triple at a time
  through the single sequential multiply-reduce datapath described
  below. Batches are laid out in the same `(lm, u, v)` iteration order
  as `mp_NTT`'s nested loops (see FSM below), so the last batch of a
  stage may be a partial batch (< 16 triples) when the stage's total
  butterfly count isn't a multiple of 16.
  - **Correction (found during implementation): this does NOT reduce
    DRAM transaction count.** This Keccak IP has no AXI burst
    capability anywhere — every DRAM access, for the DMA absorb engine
    and this engine alike, is a single-outstanding, one-beat
    req/gnt/valid transaction, with no length/burst-size field at all
    (confirmed by reading `vrf_axi_top.sv`'s `dma_*` port and the
    `axi_adapter` instantiation one level up, which is fixed to
    `SINGLE_REQ`/non-burst framing). So loading 16 triples still costs
    48 individual word transactions, same total as loading them one
    butterfly at a time — the earlier "~16x fewer DRAM round trips"
    claim in this document was wrong. `ntt_engine.sv` keeps the
    batching anyway, because it still amortizes per-butterfly FSM
    re-entry overhead and, more importantly, decouples the multiply-
    reduce pipeline from being interleaved with a DRAM wait state after
    every single butterfly (all 16 loads happen back to back, then all
    16 computes, then all 16 writebacks). A real transaction-count
    reduction would require a genuinely new burst-capable AXI master
    port, which nothing in this codebase currently demonstrates and
    which was deliberately not built here, consistent with the "keep
    hardware small" default this project has favored throughout (e.g.
    the sequential-over-pipelined multiplier choice below) and the
    observation that raw multiply/transaction throughput was never
    what profiling identified as the bottleneck.
  - **Considered and deferred**: double-buffering the 1600 bits into
    two ~8-triple halves (to overlap DMA of the next/previous batch
    with compute on the current one) and variable-shape batching that
    exploits `gm[u+m]` being constant across the whole inner `v`-loop
    (fetch one twiddle + up to `ht` pairs instead of 16 independent
    triples) were both considered. Both are real bandwidth/throughput
    wins for large-`ht` early stages, but add FSM/control complexity
    (ping-pong state tracking, or per-stage variable batch shape).
    Deferred in favor of the uniform fixed-depth-16 layout above,
    which is stage-agnostic and identical for NTT and iNTT. Worth
    revisiting only if post-implementation cycle counts show batch
    boundaries (not multiply latency) are still the bottleneck.
  - This time-multiplexes with Keccak's own use of the same state
    lanes. Safe because SHAKE calls and NTT calls never overlap in
    this single-threaded flow — no caller issues a hash and a
    butterfly at the same instant — so there is no read/write
    conflict, only a second arbitration mode alongside the existing
    CSREG-triggered / DMA-absorb modes.
- **Pipeline intermediates** (the 64-bit product `z`, the 32-bit `w`):
  new small dedicated registers — these are transient per-cycle
  pipeline state, not "storage" in the buffer sense, and don't belong
  in the shared state array (they're written every cycle the pipeline
  is active, unlike Keccak's state which is idle throughout).

### New arithmetic (unavoidable — Keccak's XOR/rotate datapath can't do this)

A single-lane Montgomery multiply-reduce, modeled on `re_bfu`'s
`mred`/`bfu_block1-4` but with the 16-way parallelism removed:

1. `z = a * b` — one 32×32→64 unsigned multiply.
2. `w = low32(z) * p0i` — one 32×32→32 unsigned multiply (only the low
   half of the product is kept).
3. `t = (z + w*p) >> 32` — a third 32×32→64 multiply, add to `z`, keep
   the upper 32 bits.
4. `d = t - p; result = (d < 0) ? d + p : d` — conditional subtract.

That's 3 multiplies total. Two implementation choices, both far smaller
than the reference's 4-lane × (2-multiply) = 8-multiplier array:

- **Sequential** (smallest): one 32×32 multiplier, reused 3 times
  per butterfly (~3 extra cycles vs. fully pipelined, minimal area) —
  the natural choice given "keep hardware small" and the fact that we
  don't need sustained per-cycle throughput (total butterfly count
  across a full KAT is in the low thousands, not millions).
  Latency budget is dominated by DRAM round-trips per operand fetch,
  not multiplier area anyway.
- **Pipelined** (if throughput matters more later): 2-3 dedicated
  multiplier instances, ~4-5 cycle latency, one butterfly initiated
  per cycle once primed — closer to `re_bfu`'s shape but still only
  1 lane wide instead of 16.

`p`/`p0i` are muxed from two small constant pairs (P1/P1_0i, P2/P2_0i),
matching the reference's `defines.v` values exactly (same field).
`mp_add`/`mp_sub` are essentially free — a 32-bit adder/subtractor plus
a conditional add-back mux, no pipeline stage of their own needed.

### Register map

| Register | Purpose |
|---|---|
| `NTT_A_ADDR` | base DRAM address of polynomial `a[]` |
| `NTT_GM_ADDR` | base DRAM address of twiddle table `gm[]`/`igm[]` |
| `NTT_LOGN` | degree parameter (log2 n; matches `mp_NTT`'s `logn` arg) |
| `NTT_P_VAL` | modulus `p` for this job (any prime, not hardcoded -- see "Widened prime support" above) |
| `NTT_P0I_VAL` | `p0i = -1/p mod 2^32` for this job, software-precomputed |
| `NTT_CTRL` | GO / DONE / MODE bits: MODE (bit 2) selects direction only -- 0 = forward (`mp_NTT`), 1 = inverse (`mp_iNTT`) |

No separate length register — `n = 1 << logn`, same convention `mp_NTT`
itself uses.

### FSM states

A small counter-driven sequencer (no wide permutation network needed
since we're one lane) — DRAM traffic happens once per 16-butterfly
batch, not once per butterfly:

```
IDLE
  -> stage index init (lm=0, u=0, v=0, v0=0); batch index init
LOAD_BATCH     -- address generator walks (lm, u, v) in mp_NTT's own
                  nested-loop order for up to 16 butterflies, fetching
                  each (gm[u+m], a[k1], a[k2]) triple one 32-bit word
                  at a time over the single-outstanding req/gnt/valid
                  port into the next free triple slot of the 1600-bit
                  register file (partial batch if fewer than 16 remain
                  in this stage)
MONTMUL        -- feed the current triple's a[k2], twiddle into the
                  multiply-reduce pipeline
MONTMUL_WAIT   -- drain pipeline latency
ADDSUB         -- x1' = x1+x2' mod p ; x2' = x1-x2' mod p (single cycle,
                  written back into the same triple's slot, in place)
TRIPLE_ADVANCE -- if triples remain in this batch, advance to the next
                  staged triple and loop to MONTMUL (register-file only,
                  no DRAM access); else fall through to WRITEBACK
WRITEBACK      -- write all completed triples' results back to a[k1],
                  a[k2] in DRAM, one 32-bit word at a time (same
                  single-outstanding port as LOAD_BATCH)
BATCH_ADVANCE  -- step to the next up-to-16-butterfly batch in (lm, u, v)
                  order; loop to LOAD_BATCH, or to DONE_HOLD when
                  lm == logn
DONE_HOLD
```

(`ntt_engine.sv`'s actual state names differ slightly in the implementation
— `LOAD_REQ`/`LOAD_WAIT`/`LOAD_WR` for the load handshake+RMW-into-array
per word, `MM_STEP` folding MONTMUL/MONTMUL_WAIT into one multi-cycle
state driven by an internal `mm_cyc` counter, `STORE_K1`/`STORE_K2` for
ADDSUB's in-place writes, `WB_REQ`/`WB_WAIT` for WRITEBACK — but the
stage/batch/triple structure above is exactly what was built.)

The index sequencing (`lm`/`u`/`v`/`v0`/`t`/`ht`) is exactly `mp_NTT`'s
own nested-loop structure, ported to hardware counters — no new
algorithmic complexity, just address generation matching what the C
loop already computes, now generating 16 butterflies' worth of
addresses per `LOAD_BATCH`/`WRITEBACK` instead of 1.

### Shared benefit

Because this accelerates `mp_NTT`/`mp_iNTT`/`mp_montymul` themselves
(the shared primitive), rather than one specific caller's loop as a
bespoke black box, any caller with the same NTT/iNTT shape benefits
from one implementation. Falcon Verify's `mq_NTT_hw()`/`mq_iNTT_hw()`
(`vrfy.c`) are the concrete example: `Zf(to_ntt_monty)`'s pubkey
transform and `Zf(verify_raw)`'s `s2*h` computation both dispatch to
this same engine, for Falcon's own prime `q=12289` — a prime never
hardcoded into the original two-prime design (see "Widened prime
support" above).

## Open questions for the implementation phase (not yet answered)

- **Resolved (2026-07-22):** register-file utilization. The engine
  batches 16 `(twiddle, x1, x2)` triples per DRAM round trip (see
  Storage and FSM sections above) instead of 1; double buffering and
  variable-shape (twiddle-reuse) batching were considered and
  explicitly deferred for simplicity. Revisit only if post-
  implementation profiling shows batch-boundary stalls dominate.
- **Resolved:** partial-batch / stage-boundary handling. `ntt_engine.sv`
  tracks `stage_bf_left_q` (butterflies remaining in the current stage,
  constant for the whole batch) and derives `is_last_triple_of_batch`
  combinationally from it plus the in-batch triple index, rather than a
  flat counter — since every stage always has exactly `n/2` butterflies
  for both `mp_NTT` and `mp_iNTT` (`m*ht = hm*t = n/2`), the stage-start
  value needs no per-stage multiply, just `n>>1`.
- **Resolved: `mp_iNTT`'s exact non-AVX2 algorithm was read from
  source directly, not assumed.** It is NOT a mirror image of `mp_NTT`
  in the way "inverse NTT" might suggest: it's Gentleman-Sande
  (decimation-in-frequency) versus `mp_NTT`'s Cooley-Tukey
  (decimation-in-time), the multiply and add/sub happen in the
  opposite order per butterfly, and critically there is NO separate
  final `n^-1` scaling pass — `mp_half()` is applied on the sum side of
  every single butterfly across all `logn` stages instead. Guessing
  this from "inverse NTT" naming alone would have produced wrong
  hardware. Both directions share one address generator via mode-muxed
  `inner_count`/`stride`/`outer` formulas and a mode mux selecting which
  operand feeds the multiplier (see `ntt_engine.sv`'s header comment
  and `mulA`).
- **Resolved: non-cacheable scratch-window discipline applies here.**
  `ntt_engine` writes `a[]` results back to DRAM as a second AXI
  master, so the same cache-coherency concern applies as any hardware
  job that writes DRAM out-of-band. `DcacheFlushOnFence`/
  `DcacheInvalidateOnFlush` are `1'b0` on this SoC config
  (`cv64a6_imac_crypto_config_pkg.sv`) — a plain `fence` does not
  flush/invalidate anything here, so scratch windows must be placed in
  a genuinely uncached PMA region (matching the `CachedRegionLength`
  boundary) rather than relying on fence semantics at all — see
  `vrfy.c`'s own scratch-window comment for Falcon's concrete window.
- **Resolved: sequential multiplier pipeline depth is 4 cycles**
  (`ntt_engine.sv`'s `MM_STEP` state, `mm_cyc` 0..3: issue `z=a*b`,
  issue `w=low32(z)*p0i`, issue `wp=w*p` and latch `sum=z+wp`, then
  finalize `d=sum_hi-p` with conditional add-back), plus 2 more cycles
  for the in-place `STORE_K1`/`STORE_K2` writes — 6 cycles of compute
  per butterfly, on top of however many single-beat req/gnt/valid round
  trips `LOAD_REQ`/`WB_REQ` take (3 loads + 2 writebacks per triple).
- Whether to also expose `mp_montymul` as a standalone single-call mode
  (for elementwise multiply passes that aren't part of an NTT butterfly
  sequence, e.g. Falcon's `mq_poly_montymul_ntt`, currently left in
  software — see "Not yet accelerated" in the falcon*-opt READMEs), or
  whether streaming those through the same engine one coefficient at a
  time is simpler to control.

## PQNTRU paper cross-analysis: SIMD/dual-issue parallelism and shuffling (2026-07-26)

Cross-checked against `2024-1754.pdf` ("PQNTRU: Acceleration of NTRU-based
Schemes via Customized Post-Quantum Processor"), to see which of their
techniques (a tightly-coupled RISC-V core with a custom 8/10-lane SIMD
ALU and dual-issue pipeline) transfer to our architecture (a single-issue
CVA6 host dispatching jobs to a loosely-coupled MMIO peripheral,
`ntt_engine.sv`, with its own AXI master). Every claim below was checked
against our actual RTL/C sources, not assumed by analogy to the paper.

**Verify-relevance**: items #1 and #2 below apply directly to the
NTT/iNTT calls already on the verify critical path (`falcon512-opt`/
`falcon1024-opt`'s `mq_NTT_hw`/`mq_iNTT_hw` calls, currently 61.7%/63.8%
of verify per `results.md`) — high priority. (The paper also covers
twiddle-factor generation from a primary root, but that only applies to
KeyGen's per-modulus table regeneration -- neither Falcon verify path
regenerates twiddle tables at runtime, so that item is out of scope here.)

### 1. Their SIMD/dual-issue parallelism vs. "parallelize via DMA"

The paper's 8/10 concurrent lanes (§3.1.3) are **not** a DMA or bus
phenomenon: they execute inside the CPU's EX stage on data already
resident in a tightly-coupled 5×16×64-bit SIMD register file, loaded
there by ordinary 64/128-bit SIMD load/store instructions issued by the
core itself. There is no AXI transaction, no external master, for the
actual butterfly math. We have no analog to that register file or ALU
replication — replicating it would mean widening CVA6's own pipeline (a
different, much larger project) or replicating N full butterfly
datapaths inside `ntt_engine.sv`, each needing its own operand traffic.

The proposal to get similar parallelism by "moving more data via DMA"
was checked directly against `axi_adapter.sv` (not assumed) and hits two
separate walls, both inside that shared CVA6 core-cache-subsystem file
(not our peripheral):

- **Burst (multi-beat) transfers**: already tried and reverted in
  Revision 1→2 of this engine (see "Batched twiddle reuse and the
  abandoned burst-DMA attempt" above) — `axi_adapter.sv` zeroes the low
  `CACHELINE_BYTE_OFFSET` address bits for any non-`SINGLE_REQ`
  transaction type (built for CVA6's own cache-line-aligned fetches),
  which silently corrupted our non-cache-aligned batch addresses.
  Confirmed on real RTL simulation before reverting, not assumed.
- **Pipelined single-beat transfers** (multiple outstanding `SINGLE_REQ`
  reads, no burst — a genuinely different mechanism from the above,
  checked specifically for this analysis since it seemed like it might
  sidestep the cache-line bug): also blocked, but for a different
  reason. `axi_adapter.sv` only tracks outstanding **write** count
  (`outstanding_aw_cnt_q`); the read path sends `SINGLE_REQ` to
  `WAIT_R_VALID` (singular) and won't accept a new address phase until
  that one read's data returns. Reads are single-outstanding by
  construction, burst or not.

Both walls sit in shared, correctness-critical core RTL used by the
CPU's own LSU — reopening either is the same cost/risk tradeoff that
motivated abandoning burst DMA the first time, and is not recommended.

**What *is* directly achievable, and matches the paper's actual named
goal for this problem (§4.2.2, "layer merging" — not SIMD width) is
purely internal to `ntt_engine.sv`'s own FSM, no bus changes needed.**
Their baseline problem: writing back every NTT layer to memory and
reloading for the next layer is wasteful; they keep 2-3 consecutive
layers' operands resident in registers and write back only once per
merged group (their Tables 3-6, ~66-78% memory-access reduction). We do
the same wasteful thing today: `BATCH_ADVANCE` (`ntt_engine.sv`) writes
every batch back to DRAM at the end of *each* stage, and the next
stage's `BATCH_INIT`/`LOAD_K1_REQ` reloads everything from scratch — for
`n=1024` that's 10 full read+write passes over the array per NTT call.
`k1_batch_q`/`k2_batch_q[0:15]` already hold up to 16 operands on-chip;
we're discarding that residency at exactly the point (every stage
boundary) where the paper keeps it. This is real, sizeable, and would
directly reduce NTT/iNTT's share of verify (currently the single largest
cost in both Falcon variants). **Not a small tweak, though**: our current
batch-selection strategy ("16 consecutive `v` for one `u`," chosen for
twiddle reuse within a single stage) is a different address pattern from
the paper's cross-stage-valid selection (their Table 3's
`0, N/8, 2N/8, ..., 7N/8`) and would need its own re-derivation for
cross-stage validity, not a relabeling of the existing one. This is the
top candidate from this analysis for a next implementation pass.

### 2. Their shuffling mechanism (§3.1.3, Table 1)

Their shuffle ops solve a problem specific to *their* representation:
8 coefficients are bit-packed as lanes inside one 320-bit register, and
when the butterfly distance shrinks below 8 (their Table 4's "last 3
layers"), the two operands can land in the same physical register at
different bit offsets, or need realigning across two registers — hence
`input shuffling`/`output shuffling`/`reverse shuffling` to permute
lanes before the ALU can act on the correct pairs.

We don't have that problem: `k1_batch_q[0:15]`/`k2_batch_q[0:15]` are
already an **array of 16 separately-addressed registers**, not packed
lanes in one word — `triple_idx_q` already does, for free, exactly what
their shuffle op does at instruction cost: pick which stored element
pairs with which. A literal "shuffle unit" would be new hardware solving
a problem this architecture doesn't have, so it is **not** recommended
for porting as-is.

The underlying *indexing* problem their Table 1/4 encode — "which
pairing of resident operands is correct changes as you move to the next
merged layer, and that remapping isn't a simple stride" — **is** real
and directly relevant if item #1 (layer merging) is pursued: it would
show up as more complex index arithmetic in `BATCH_INIT`/`MM_STEP`
(which batch slot pairs with which, per sub-layer, within a merged
group), not as a new ALU primitive. Their Table 3/4 are worth keeping as
a reference derivation for that indexing work, even though the
implementation mechanism differs (index arithmetic vs. bit-permute op).

### Recommendation

Ranked by verify-focused priority: **layer merging (#1)** is the
strongest candidate for a next pass — real, sizeable (paper reports
66-78% memory-access reduction on the analogous problem), purely
internal to `ntt_engine.sv`, and directly attacks NTT/iNTT's
currently-dominant share of verify cost, but requires a genuine
address-generator redesign (not incremental). **Shuffling (#2)** isn't
something to port as new hardware; its lesson folds into #1's indexing
work if pursued.
