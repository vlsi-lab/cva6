# NTT/Montgomery-multiply accelerator — design scope (2026-07-21, updated 2026-07-22)

## Status

**Implemented and integrated (2026-07-22).** `keccak_ip/rtl/ntt_engine.sv`,
the `NTT_*` register additions to `keccak_ip/keccak.hjson`, the
`keccak_axi_top.sv` wiring, `tests/hawk-256-keccak/ntt_engine_test.c`, and
software dispatchers in both `hawk_vrfy.c` (Verify) and `ng_mp31.c`
(KeyGen/Sign, the real exported `mp_NTT`/`mp_iNTT` symbols) all exist and
have been confirmed correct end-to-end on real verilator/DV simulation,
not just compiled. Timeline of what was actually measured:

| Step | What changed | KeyGen | Sign | Verify |
|---|---|---:|---:|---:|
| Keccak+Gauss baseline | (pre-NTT-work) | 8,779,383 | ~325,396 | 562,324 |
| `hawk_vrfy.c` redirect | plain `mp_NTT` only, P1/P2-guarded | 8,781,648 (noise) | 325,474 (noise) | **512,078** |
| `ng_mp31.c` redirect | real `mp_NTT`/`mp_iNTT`, P1/P2-guarded | **8,201,650** | 326,345 (noise) | 509,936 |
| Widened prime support | generic `NTT_P_VAL`/`NTT_P0I_VAL`, any prime | 8,141,546 | 326,777 (noise) | 509,207 (noise) |
| Batched-twiddle reuse + autoadj HW mode (2026-07-23) | see below | 7,786,426 | 323,507 | **439,096** |
| + `vect_FFT`/`vect_iFFT` HW (Revision 3, 2026-07-23) | see "Fixed-point FFT scoping" below | **7,707,400** | 326,247 (noise) | 442,453 (noise) |

Second-to-last row: −4.4% KeyGen, −1.0% Sign, −13.8% Verify versus the
row above it. Two independent changes landed together here —
`mp_NTT_autoadj`'s reduced-butterfly phase moved to hardware (mode=2, see
the corrected section below, superseding the earlier "stays
software-only" call), and `ntt_engine.sv` was reworked to batch up to 16
consecutive butterflies' twiddle fetches into one instead of fetching
per-butterfly (see "Batched twiddle reuse and the abandoned burst-DMA
attempt" below). Verify's larger win is expected: it's the caller that
actually exercises the autoadj path.

Last row: a further −1.0% KeyGen (79,026 cycles), Sign/Verify unchanged
(neither calls `vect_FFT`/`vect_iFFT` -- see "Fixed-point FFT scoping"
below for why this KeyGen win is real but smaller than the underlying
1.68x-3.7x per-call FFT/iFFT speedup would suggest: `babai_loop`'s other
half, `poly_sub_scaled`, dominates that loop's cost and is still
untouched).

`Keygen OK / Sign OK / Verify OK` held at every step. The `hawk_vrfy.c`
redirect only ever patches that file's own private, non-exported `mp_NTT`
copy — it has zero effect on `ng_hawk.c`/`ng_ntru.c`, which is why the
`ng_mp31.c` redirect (on the real, exported symbols) was a necessary
second step, not a duplicate of the first.

Two premises below turned out to be wrong once real hardware and real
callers were checked, and are corrected in place further down:
- "No AXI burst capability" (search that phrase): this accelerator's DMA
  path, like `gauss_sampler.sv`'s, is a single-outstanding req/gnt/valid
  port — the 16-triple register-file batching's real benefit is
  amortizing per-butterfly FSM overhead and decoupling the multiply-reduce
  pipeline from DRAM waits, not cutting DRAM transaction count. (A real
  burst DMA path was later built and measured anyway — see "Batched
  twiddle reuse and the abandoned burst-DMA attempt" — and abandoned for
  an architectural reason unrelated to this original reasoning, which
  ended up correctly describing the final shipped design either way.)
- The original 1-bit `NTT_PRIME_SEL` (P1/P2 only) undersold KeyGen's
  actual opportunity: `ng_ntru.c`'s `solve_NTRU()` (KeyGen's 80%
  bottleneck) calls `mp_NTT`/`mp_iNTT` over the full `PRIMES[0..slen]`
  table, not just P1/P2 — see "Widened prime support" below.

This is a scoping exercise turned implementation, the same way the
Gaussian CDT sampler was scoped before being implemented (see
`tests/hawk-256-keccak/gauss_sampler_test.c` / `keccak_ip/rtl/gauss_sampler.sv`
for that precedent).

## Widened prime support (2026-07-22)

The original design (register map and RTL both) hardcoded exactly two
primes (P1, P2) behind a 1-bit `NTT_PRIME_SEL` register, matching what
`hawk_vrfy.c` alone needs. Once the real call graph was traced (see
`ng_ntru.c`'s/`ng_poly.c`'s wide `PRIMES[0..slen]` loops in `solve_NTRU()`,
KeyGen's actual 80% bottleneck), this was clearly too narrow: those loops
use dozens of different primes per KeyGen attempt, and only the ones that
happened to be `PRIMES[0]`/`PRIMES[1]` (P1/P2) could ever reach hardware.

**Change:** `NTT_PRIME_SEL` (1 bit, 2 hardcoded prime/p0i pairs as RTL
`localparam`s) was replaced with `NTT_P_VAL`/`NTT_P0I_VAL` (two 32-bit
registers, software supplies both directly — it already has `p0i`
precomputed per prime in the `PRIMES[]` table, so this is free on the
software side). Inside `ntt_engine.sv`, this removed the `p_sel`/`p0i_sel`
2-entry mux entirely and replaced it with a straight `p_q`/`p0i_q`
register pair latched at job start — the Montgomery multiply-reduce
datapath already treated `p`/`p0i` as plain inputs throughout (per-
butterfly `mp_montymul`/`mp_add`/`mp_sub`/`mp_half` never referenced a
specific prime value), so **this was a net reduction in RTL**, not an
addition: two hardcoded 32-bit constants and a mux disappear, replaced by
two register fields the reg-file infrastructure already provides for
free. No FSM, batching, or address-generator logic changed at all.

Software dispatchers in `ng_mp31.c` and `hawk_vrfy.c` dropped their
`p==P1||p==P2` guards accordingly. The only guard left is a size
threshold, `NTT_HW_MIN_LOGN = 2` (`logn<2` stays in software): below that,
the fixed per-job overhead (5 register writes, the DONE poll, the
scratch-window copy) isn't worth it — `logn==0` is already a no-op in
`mp_NTT`/`mp_iNTT` themselves, and `logn==1` is a single butterfly. This
threshold is a judgment call, not derived from profiling; worth revisiting
if a future profile shows it's miscalibrated.

`ntt_engine_test.c` was extended to exercise `PRIMES[2]`/`PRIMES[3]` (real
entries from the wide table, not just P1/P2) alongside the original two,
specifically to prove the widened registers work for genuinely arbitrary
primes rather than continuing to pass by coincidence -- confirmed: all 16
cases (2 logn sizes x 4 primes x 2 directions) pass with 0 mismatches on
real RTL simulation, and the full KAT still passes end to end.

**Measured KeyGen impact was small (−0.7%, 8,201,650 → 8,141,546 cycles),
smaller than the "solve_NTRU is 80% of KeyGen" profiling number might
suggest.** That 80% figure was always `solve_NTRU()`'s *total* cost, most
of which is other big-integer/CRT arithmetic (`ng_zint31.c`), not
specifically `mp_NTT`/`mp_iNTT` calls. Now that every `PRIMES[u]` call is
hardware-eligible, either the NTT-specific share of that 80% isn't the
dominant piece, or the fixed per-job overhead (5 register writes, DONE
poll, scratch-window copy) paid on every one of the many — often small —
calls threaded through the recursion is eating into the win. Distinguishing
those two explanations would need a finer profiling pass than exists
today; not guessed at here.

## Single-operation golden-model benchmarks (2026-07-22)

Mirroring `tests/keccak64`'s software/hardware golden-model pattern
(`keccak_noopt.c`/`keccak_axi.c`/`keccak_single_call_cost.c`):
`ntt_sw_bench.c` (calls `mp_NTT_sw`/`mp_iNTT_sw` directly, bypassing the
hardware dispatcher entirely), `ntt_hw_bench.c` (calls `mp_NTT_hw`
directly), and `ntt_hw_cost_breakdown.c` (pokes registers directly,
sub-phase-timed). All three use n=256, P1 — HAWK-256's real size and one
of its two hardware-supported primes — and are cycle-counted via the
`mcycle` CSR in isolation (no KAT, no other traffic). Correctness is a
self-contained round-trip check (`mp_iNTT(mp_NTT(x)) == x`, exact — no
external expected-vector constants needed since `mp_iNTT`'s `n^-1`
scaling is built into every stage).

| Operation | Software | Hardware | Speedup |
|---|---:|---:|---:|
| NTT (n=256, P1) | 35,255 cycles | 28,574 cycles | 1.23x |
| iNTT (n=256, P1) | 42,176 cycles | 28,563 cycles | 1.48x |

**Hardware cost breakdown for one NTT call** (`ntt_hw_cost_breakdown.c`):

| Phase | Cycles | Share |
|---|---:|---:|
| scratch-copy-in (256 stores) | 1,439 | 5% |
| **regs+GO+poll (hardware compute+handshake)** | **24,706** | **87%** |
| scratch-copy-out (256 loads) | 2,214 | 8% |
| **Total** | 28,487 | (≈ full-round-trip number above, small measurement-boundary difference) |

**This overturns the working assumption from earlier in this session**
that fixed per-call overhead (register writes, scratch-window copy) was
the dominant cost holding back the win. It is not — it's a modest 13%.
The 87% "regs+GO+poll" bucket is the accelerator's *own* internal
per-butterfly cost: 1024 butterflies for n=256 (`n/2 * logn`), 24,706
cycles / 1024 ≈ 24.1 cycles/butterfly — far above the ~6-cycle compute
estimate (4-cycle `MM_STEP` + 2-cycle `STORE_K1`/`STORE_K2`), confirming
the design doc's own "no AXI burst capability" caveat (see above) is the
actual bottleneck in practice, not just a theoretical concern: every one
of the 5 words per butterfly (3 loads, 2 writebacks) pays a full
single-beat req/gnt/valid round trip inside `ntt_engine.sv`'s FSM, with
no way to pipeline or coalesce them.

**Why software is more competitive than a "hardware accelerator" label
might suggest:** HAWK-256's `a[]` is 256×4 = 1KB — comfortably fits in a
typical L1 D$, so the CPU's *own* scalar NTT loop benefits from cache
locality on repeated access to the same small array across all `logn`
stages. `ntt_engine.sv`, as a separate AXI master with no cache of its
own, pays full DRAM latency on every single word, every time, with no
such benefit. This is the real explanation for the modest 1.2-1.5x
single-operation speedup, and it directly explains the small KeyGen/
Verify wins measured in the full KAT (see the timeline table above and
the bottleneck analysis in the session's chat transcript): the
accelerator's per-operation advantage over software was simply smaller
than the initial profiling-driven framing ("solve_NTRU is 80% of
KeyGen") implied, independent of how many call sites got redirected.

## `mp_NTT_autoadj`'s reduced-butterfly phase: initially deferred, later added

**Superseded below (2026-07-23): the reduced-butterfly phase was
ultimately added to hardware as `job_mode_i==2'b10`, see `ntt_engine.sv`'s
header comment for the derivation. The unfold step described here stays
software-only regardless — only the loop that follows it moved.** Kept
for the original reasoning, which is still why the unfold step alone
wasn't worth chasing into hardware.

`hawk_vrfy.c`'s `mp_NTT_autoadj` (used for `q00` in `vrfy_ntt_norm`, via
`mp_poly_to_NTT_autoadj`) was considered for hardware support alongside
the prime widening, but initially deferred after reading its actual
non-AVX2 body (`hawk_vrfy.c:730-761` at the time of this analysis):

```c
size_t hn = (size_t)1 << (logn - 1);
uint32_t s1 = gm[1];
size_t qn = hn >> 1;
for (size_t u = 1; u < qn; u ++) {                 /* "unfold" step */
    a[u]      = mp_sub(a[u],      mp_montymul(a[hn-u], s1, p, p0i), p);
    a[hn - u] = mp_sub(a[hn - u], mp_montymul(a[u],    s1, p, p0i), p);
}
a[qn] = mp_sub(a[qn], mp_montymul(a[qn], s1, p, p0i), p);

size_t t = hn;
for (unsigned lm = 1; lm < logn; lm ++) {
    size_t m = (size_t)1 << lm;
    ...
    for (size_t u = 0; u < (m >> 1); u ++) {       /* HALF of m, not m */
        uint32_t s = gm[u + m];                     /* twiddle offset still m */
        ...
    }
    t = ht;
}
```

The earlier research summary approximated this as "a full CT NTT of half
the size" — close, but not quite right in a way that matters: the loop
bound is `m >> 1` while the twiddle offset stays `u + m` (the *full* `m`,
not `m >> 1`). `ntt_engine.sv`'s address generator couples "how many `u`
values this stage has" and "the twiddle offset for this stage" into one
register (`outer_q`, serving both roles by design — see the FSM section
below). Serving `mp_NTT_autoadj` correctly would require decoupling those
two roles (an `outer_limit = outer_q >> 1` loop bound, separate from
`outer_q` itself still used for twiddle indexing) plus a new prologue
mode for the O(n/4) unfold step — a real, if small, RTL addition, not a
software-only reuse of the existing forward-NTT mode.

Given the explicit priority for this round of work ("best performance
with the lowest hardware possible"), and that forcing this algorithm onto
the existing engine via an approximation would risk a silent correctness
bug in crypto code with no clean way to self-check it, `mp_NTT_autoadj`
was initially left running entirely in software. It represented roughly
the smaller share of `vrfy_ntt_norm`'s transform work (3 full `mp_NTT`
calls, hardware, vs. 2 half-size `mp_NTT_autoadj` calls, software, per
prime) — real but secondary, and flagged as "the right next candidate if
a future round decides a small addressing-mode addition is worth it."

**That addition was made.** The `outer_limit`/twiddle-offset decoupling
turned out not to need new address-generator logic at all: this engine's
per-stage butterfly count (`stage_bf_left_q`, tracked as `n_q>>1`, not a
separately-tracked loop bound) already determines how many `u` values get
visited each stage. Calling the SAME engine with `job_logn_i =
(autoadj's logn - 1)` — making `n_q` equal autoadj's `hn` automatically —
and starting `outer_q` at 2 instead of 1 (`job_mode_i[1]`) reproduces the
reduced loop (`u < m>>1`, twiddle offset `u+m`) exactly, with zero new
registers or states. The O(n/4) unfold step (reflected `a[u]`/`a[hn-u]`
indexing, single twiddle `gm[1]`) still stays software-only — it doesn't
fit this engine's regular butterfly shape and is a small, cheap loop on
its own. Verified correct on real RTL simulation
(`ntt_engine_test.c`'s `autoadj-reduced` cases, self-contained software
reference transliterated from `hawk_vrfy.c`'s non-AVX2 body, 8/8 passing
across logn=3/8 × all four `PRIMES[]` entries) and end-to-end (KAT still
`Verify OK`). Measured impact: Verify dropped 509,207 → 439,096 cycles
(−13.8%) in the same step as the batched-twiddle-reuse change below, so
this isn't attributable to autoadj alone — see the Status table.

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
from `keccak_dma_ctrl.sv`/`gauss_sampler.sv`.

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
merit and needed no burst-related changes to work. See the Status table
for the measured combined impact of batched-twiddle-reuse + the autoadj
hardware mode above.

## Why

Cycle profiling of the Keccak+Gauss-accelerated build (see
`tests/hawk-256-keccak-profile/README.md`) showed that, with SHA3/SHAKE
already offloaded to hardware, KeyGen and Verify are now dominated by
non-hash arithmetic:

| Build phase | Dominant sub-phase | Share |
|---|---|---:|
| KeyGen (8.78M cycles) | `solve_NTRU` (`ng_ntru.c`) | 80% |
| Verify (562K cycles)  | `vrfy_ntt_norm` (`hawk_vrfy.c`) | 76% |

Both bottom out in the same three C primitives, from `ng_mp31.c`:
`mp_NTT`, `mp_iNTT`, `mp_montymul` — `ng_ntru.c` alone calls them 108
times. So rather than building bespoke hardware for "the KeyGen problem"
and "the Verify problem" separately, the highest-leverage target is to
hardware-accelerate these three shared primitives directly, and let both
callers benefit automatically — the same way every `shake_*` call
already gets transparently redirected to the Keccak AXI peripheral
without `hawk_sign.c`/`hawk_vrfy.c` needing per-call-site awareness.

## What the reference design does (and why we don't copy it wholesale)

`tches2026_3-paper76-supplementary_material/rtl/bfu/` is a complete
standalone HAWK ASIC arithmetic engine — no host CPU, no DRAM:

- `buffer.sv`: 4-bank dual-port BRAM scratchpad, `BRAM_DEPTH(512) ×
  VEC_BITS(128) × 4 banks` ≈ **32 KB on-chip**, holding every polynomial
  the whole HAWK computation ever touches (see the `ADDR_*` map in
  `defines.v`).
- `bfu_datapath.sv`: 4 parallel `re_bfu` cores, each consuming 4×32-bit
  words/cycle → 16 coefficients/cycle, `BFU_PIPE_STAGES=7` deep, plus a
  twiddle ROM (`tw_rom.sv`), permutation networks, pre/post-shifters.
- `re_bfu.sv` (1158 lines): the actual per-lane kernel — a pipelined
  32×32 Montgomery multiplier (`bfu_block1-4`, `mred`) + modular
  add/sub-with-reduce (`addred32`/`subred32`, and 16-bit variants for
  P0=18433).
- `msum4.sv`: a streaming Montgomery multiply-accumulate over two primes
  at once.

None of the 32 KB buffer or the 16-wide parallelism fits our situation:
CVA6's DRAM already holds every polynomial, and the *entire* NTT-domain
workload across a full KAT run costs ~7M (KeyGen) + ~430K (Verify)
cycles total — nowhere near needing 16-wide sustained throughput.
Duplicating that scale would be pure waste. What *is* worth borrowing is
the per-lane arithmetic kernel shape (`re_bfu`'s Montgomery
multiply/reduce + modular add/sub), scaled down to one lane.

## The actual C algorithm being targeted

`mp_NTT` (`ng_mp31.c:543`, non-AVX2 path — the one CVA6 actually runs) is
a textbook iterative decimation-in-time NTT:

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

`mp_iNTT` is the mirror-image (decimation-in-frequency, same butterfly
shape). `mp_montymul` (`ng_inner.h:548`) is standard word-level
Montgomery reduction, R=2^32:

```c
uint64_t z = (uint64_t)a * (uint64_t)b;
uint32_t w = (uint32_t)z * p0i;
uint32_t d = (uint32_t)((z + (uint64_t)w * (uint64_t)p) >> 32) - p;
return d + (p & tbmask(d));   /* conditional add-back */
```

`mp_add`/`mp_sub` are a 32-bit add/sub plus one conditional add-back —
essentially free in hardware (single cycle, no multiplier involved).

The two moduli in play are both ~31-bit primes:
`P1 = 2147473409`, `P2 = 2147389441` (matching the reference design's
`P1`/`P2` defines exactly — same field, unsurprisingly, since both
implementations are HAWK). `vrfy_ntt_norm` uses both, alternately, in a
`for (i = 0; i < 2; i++)` loop; `solve_NTRU`'s NTT calls are typically
single-prime per call.

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

Exactly like `gauss_sampler.sv` and `keccak_dma_ctrl.sv` already do:
operands and twiddle factors stream to/from CVA6 DRAM over the
accelerator's existing AXI master. No new on-chip buffer or ROM.

- **Twiddle tables** (`gm[]`/`igm[]`): software already builds these via
  `mp_mkgm`/`mp_mkigm` (`ng_mp31.c`) — no hardware table-generation
  needed at all, just point the engine at the existing DRAM array the
  same way `SAMP_T_ADDR` points at the sampler's input buffer today.
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
  - **Correction (found during implementation, 2026-07-22): this does
    NOT reduce DRAM transaction count.** This Keccak IP has no AXI
    burst capability anywhere — `gauss_sampler.sv`'s own `TREQ`/`XREQ`
    states already establish that every DRAM access, for the DMA
    absorb engine and the sampler alike, is a single-outstanding,
    one-beat req/gnt/valid transaction, with no length/burst-size
    field at all (confirmed by reading `keccak_axi_top.sv`'s `dma_*`
    port and the `axi_adapter` instantiation one level up, which is
    fixed to `SINGLE_REQ`/non-burst framing). So loading 16 triples
    still costs 48 individual word transactions, same total as loading
    them one butterfly at a time — the earlier "~16x fewer DRAM round
    trips" claim in this document was wrong. `ntt_engine.sv` keeps the
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
    this single-threaded flow — KeyGen/Verify never issue a hash and a
    butterfly at the same instant — so there is no read/write
    conflict, only a third arbitration mode alongside the existing
    CSREG-triggered / DMA-absorb / Gauss-sampler modes (mirroring
    `samp_busy` in `keccak_axi_top.sv`).
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

### Register map (mirrors the existing `SAMP_*` pattern in `keccak.hjson`)

| Register | Purpose |
|---|---|
| `NTT_A_ADDR` | base DRAM address of polynomial `a[]` |
| `NTT_GM_ADDR` | base DRAM address of twiddle table `gm[]`/`igm[]` |
| `NTT_LOGN` | degree parameter (log2 n; matches `mp_NTT`'s `logn` arg) |
| `NTT_P_VAL` | modulus `p` for this job (widened 2026-07-22: any prime, not just P1/P2 -- see "Widened prime support" above) |
| `NTT_P0I_VAL` | `p0i = -1/p mod 2^32` for this job, software-precomputed |
| `NTT_CTRL` | GO / DONE / MODE (NTT vs INTT) bits |

No separate length register — `n = 1 << logn`, same convention `mp_NTT`
itself uses.

### FSM states

Mirrors `gauss_sampler.sv`'s shape (small counter-driven sequencer, no
wide permutation network needed since we're one lane) — DRAM traffic
now happens once per 16-butterfly batch, not once per butterfly:

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
(the shared primitive), rather than "the vrfy_ntt_norm loop" or "the
solve_NTRU loop" as bespoke black boxes, both call sites benefit from
one implementation:

- `solve_NTRU` (`ng_ntru.c`, 108 call sites, 80% of KeyGen) — calls at
  varying degrees during its recursive lattice-reduction steps, all
  supported since `logn` is just a register input.
- `vrfy_ntt_norm` (`hawk_vrfy.c`, 76% of Verify) — on closer reading,
  this sub-phase is richer than a simple accumulate: per prime (P1 then
  P2) it does 2 full NTTs (`mp_poly_to_NTT` on `t1` and `t0`) + 1
  auto-adjoint NTT reused twice (`q00`) + a serial batch modular
  inversion (Montgomery's trick: a chain of `mp_montymul` calls, plus
  exactly one true modular inverse per prime — rare enough to leave in
  software, e.g. via Fermat's-little-theorem exponentiation reusing the
  same multiply-reduce unit) + several full-array elementwise
  `mp_montymul`/`mp_add` passes. All of these bottom out in the same
  `mp_montymul`/`mp_NTT` primitives this unit accelerates.

## Open questions for the implementation phase (not yet answered)

- **Resolved (2026-07-22):** register-file utilization. The engine
  batches 16 `(twiddle, x1, x2)` triples per DRAM round trip (see
  Storage and FSM sections above) instead of 1; double buffering and
  variable-shape (twiddle-reuse) batching were considered and
  explicitly deferred for simplicity. Revisit only if post-
  implementation profiling shows batch-boundary stalls dominate.
- **Resolved (2026-07-22):** partial-batch / stage-boundary handling.
  `ntt_engine.sv` tracks `stage_bf_left_q` (butterflies remaining in
  the current stage, constant for the whole batch) and derives
  `is_last_triple_of_batch` combinationally from it plus the in-batch
  triple index, rather than a flat counter — since every stage always
  has exactly `n/2` butterflies for both `mp_NTT` and `mp_iNTT`
  (`m*ht = hm*t = n/2`, verified against `ng_mp31.c`), the stage-start
  value needs no per-stage multiply, just `n>>1`.
- **Resolved (2026-07-22): `mp_iNTT`'s exact non-AVX2 algorithm was
  read from `ng_mp31.c` directly, not assumed.** It is NOT a mirror
  image of `mp_NTT` in the way "inverse NTT" might suggest: it's
  Gentleman-Sande (decimation-in-frequency) versus `mp_NTT`'s
  Cooley-Tukey (decimation-in-time), the multiply and add/sub happen
  in the opposite order per butterfly, and critically there is NO
  separate final `n^-1` scaling pass — `mp_half()` is applied on the
  sum side of every single butterfly across all `logn` stages instead.
  Guessing this from "inverse NTT" naming alone would have produced
  wrong hardware; both algorithms and `mp_montymul`/`mp_add`/`mp_sub`/
  `mp_half` were transcribed from `ng_mp31.c`/`ng_inner.h` with exact
  line references before writing `ntt_engine.sv`. Both directions
  share one address generator via mode-muxed `inner_count`/`stride`/
  `outer` formulas and a mode mux selecting which operand feeds the
  multiplier (see `ntt_engine.sv`'s header comment and `mulA`).
- **Resolved (2026-07-22): software-side integration shape.**
  `tests/hawk-256-keccak/ntt_engine_test.c` establishes the pattern —
  register pokes via the reggen-generated `NTT_*_REG_OFFSET` defines,
  GO/DONE poll loop (same shape as `gauss_sampler_test.c`) — but for
  `a[]`/`gm[]`/`igm[]`, not `mp_NTT_hw()`/`mp_iNTT_hw()` wrapper
  functions transparently swapped into `ng_mp31.c` yet; that
  integration into the real KeyGen/Verify call sites is still future
  work, only the standalone HW-vs-SW correctness test exists so far.
- **Resolved (2026-07-22): non-cacheable scratch-window discipline
  DOES apply here, and differs from `gauss_sampler_test.c`'s own
  (now-stale) assumption.** `ntt_engine` writes `a[]` results back to
  DRAM as a second AXI master, same as the sampler, so the same
  cache-coherency concern applies. `gauss_sampler_test.c`'s comment
  assumes `DcacheFlushOnFence`/`DcacheInvalidateOnFlush` are enabled,
  but the scoped fix (see SESSION_SUMMARY_2026-07-22.md) reverted both
  to `1'b0` in `cv64a6_imac_crypto_config_pkg.sv` — a plain `fence`
  no longer flushes/invalidates anything on this SoC config, which
  makes that particular unit test's coherency comment stale (worth a
  follow-up look, separate from this task). `ntt_engine_test.c` avoids
  the question entirely by placing `a[]`/`gm[]`/`igm[]` in the same
  uncached DRAM window convention as `GAUSS_HW_SCRATCH_ADDR`
  (`NTT_HW_SCRATCH_ADDR = 0x80F00000`, matching the PMA's
  `CachedRegionLength` boundary) rather than relying on fence
  semantics at all.
- **Resolved (2026-07-22): sequential multiplier pipeline depth is 4
  cycles** (`ntt_engine.sv`'s `MM_STEP` state, `mm_cyc` 0..3: issue
  `z=a*b`, issue `w=low32(z)*p0i`, issue `wp=w*p` and latch `sum=z+wp`,
  then finalize `d=sum_hi-p` with conditional add-back), plus 2 more
  cycles for the in-place `STORE_K1`/`STORE_K2` writes — 6 cycles of
  compute per butterfly, on top of however many single-beat req/gnt/
  valid round trips `LOAD_REQ`/`WB_REQ` take (3 loads + 2 writebacks
  per triple). Not yet cycle-accurate against actual simulated AXI
  latency (that requires running `run_ntt_engine_test.sh`), but the
  structural depth itself is now fixed by the implementation rather
  than an open estimate.
- How `mp_montymul_x8`/AVX2-only call sites in `ng_mp31.c` map to the
  non-AVX2 path CVA6 actually compiles (confirmed above they're
  `#if NTRUGEN_AVX2`-gated and unused on this target, but worth a final
  grep before implementation to make sure no other AVX2-only code path
  sneaks into the RV64 build).
- Whether to also expose `mp_montymul` as a standalone single-call mode
  (for the elementwise passes in `vrfy_ntt_norm` that aren't part of an
  NTT butterfly sequence), or whether streaming those through the same
  engine one coefficient at a time is simpler to control.
- Still open: wrapping this into `mp_NTT_hw()`/`mp_iNTT_hw()` and
  transparently swapping them in behind the real `mp_NTT`/`mp_iNTT`
  call sites in `ng_mp31.c` (same pattern as `shake_*`'s hardware
  residency in `sha3.c`) — `ntt_engine_test.c` only proves the hardware
  itself is correct in isolation, it doesn't yet touch KeyGen/Verify.

(The three items above are historical — resolved by the widened-prime,
autoadj, and dispatcher-redirect work documented earlier in this file.
Left as-is rather than deleted, matching this doc's living-document
style: it's a record of what was open at each point, not just the
current state.)

## KeyGen deep profile: what's left after NTT/iNTT hardware (2026-07-23)

With `mp_NTT`/`mp_iNTT` hardware-accelerated and the KAT passing (see
the Status table above, final row: KeyGen 7,786,426 cycles), the
measured end-to-end speedup for KeyGen was only **1.28x** versus the
pure-software baseline (`HAWK.md`: 9,948,715 cycles). That's much lower
than Sign's 2.63x or even Verify's 1.38x, and the reason is now measured,
not guessed: **`mp_NTT`/`mp_iNTT` calls are only 18.0% of KeyGen's total
cycles.** The other 82% was never going to move no matter how fast the
NTT engine got.

New profiling instrumentation was added directly inside `ng_ntru.c`
(accumulator-based, not the single-shot `PROF_BEGIN`/`PROF_END` macros
in `profiling.h` — `solve_NTRU_intermediate()` is called 7 times per
`solve_NTRU()` from a plain loop, not recursively, so per-call
accumulation is safe and correct, unlike a shared single-slot timer
would be for a genuinely recursive call). Measured on real RTL
simulation, one full KAT run, KeyGen = 7,787,000 cycles:

| `solve_NTRU()` stage | Cycles | % of KeyGen | Calls |
|---|---:|---:|---:|
| `solve_NTRU_deepest` | 1,142,375 | 14.6% | 1 |
| `solve_NTRU_intermediate` | 3,566,497 | **45.8%** | 7 |
| `solve_NTRU_depth0` | 1,510,316 | 19.3% | 1 |
| **Total (`solve_NTRU`)** | **6,219,188** | **79.9%** | — |

`solve_NTRU_intermediate` sub-phases (summed across all 7 calls):

| Sub-phase | Cycles | % of KeyGen | What it is |
|---|---:|---:|---|
| **`babai_loop`** | **2,132,832** | **27.3%** | Babai round-off reduction loop: fixed-point FFT (`vect_FFT`/`vect_mul_fft`/`vect_iFFT`, `ng_fxp.c`) + big-integer scaled subtraction (`poly_sub_scaled`/`poly_sub_scaled_ntt`/`poly_sub_kf_scaled_depth1`), 192 iterations total across all 7 calls |
| `funreduced` | 464,889 | 5.9% | RNS+NTT loop building the unreduced F (mostly `mp_NTT`/`mp_iNTT` — already counted in the 18.0% NTT total below, so this overlaps rather than adds) |
| `babai_setup` | 323,829 | 4.1% | Fixed-point conversion + one `vect_FFT` call, before the reduction loop starts |
| `crt` | 322,154 | 4.1% | `zint_rebuild_CRT` — big-integer CRT reconstruction |
| `fgprep` | 156,062 | 2.0% | Retrieving/computing (f,g) at this depth |
| (unaccounted) | ~166,731 | 2.1% | Loop/pointer bookkeeping between the phases above |

For reference: all `mp_NTT`/`mp_iNTT` calls anywhere in KeyGen (already
hardware, the thing whose 18.0% share explains the capped 1.28x) =
1,403,667 cycles.

**Headline finding: `babai_loop` alone (27.3%) is bigger than all
NTT/iNTT combined (18.0%), and uses a completely different transform —
fixed-point real/imaginary FFT, not modular NTT — that our current
`ntt_engine.sv` does not implement.** `solve_NTRU_depth0` (19.3%,
one call, not yet broken down internally the same way) also leans on
`vect_FFT`/`vect_div_autoadj_fft`/`vect_iFFT` for its own Babai-style
division step, per a direct read of its source, on top of several
`mp_NTT`/`mp_iNTT` calls already counted in the 18.0% figure.

This matches, rather than contradicts, `TCHES2026_3_27.pdf` (HawkPU):
that paper's accelerator explicitly excludes KeyGen ("future work...
key generation support can be implemented by introducing additional
control logic to reuse existing resources within the arithmetic
module") — but its own arithmetic module already unifies NTT *and*
fixed-point FFT on the same reconfigurable BFU cores (their Section
4.1), because HAWK's algorithm needs both regardless of which phase
you're accelerating. A KeyGen-side fixed-point FFT engine is exactly
the kind of contribution that paper left on the table.

## Fixed-point FFT scoping: `vect_FFT`/`vect_iFFT` for `babai_loop` (2026-07-23)

Following the same process as the original NTT scoping: read the real
non-AVX2 source CVA6 compiles (not the AVX2 paths, `#if NTRUGEN_AVX2`-
gated and unused here), compare against what's already built, identify
what's reusable versus genuinely new.

### The algorithm (`ng_fxp.c`, scalar/non-AVX2 path)

`vect_FFT` (forward) and `vect_iFFT` (inverse) operate on `fxr` — a
64-bit fixed-point type, Q32.32 (top 32 bits integral, bottom 32
fractional), wrapped in a struct specifically so the compiler flags any
accidental use of native arithmetic operators on it (`ng_inner.h:958`).
Because the transformed polynomials are real-valued, only the first
`n/2` fixed-point pairs are kept as `fxc` (complex: `{fxr re; fxr im;}`)
— half the storage of a naive complex FFT, the same trick the HawkPU
paper describes exploiting (their Eq. 2, `f(z̄) = f(z)‾`).

```c
void vect_FFT(unsigned logn, fxr *f)
{
	size_t hn = (size_t)1 << (logn - 1);
	size_t t = hn;
	for (unsigned lm = 1; lm < logn; lm++) {
		size_t m = (size_t)1 << lm;
		size_t ht = t >> 1;
		size_t j0 = 0;
		size_t hm = m >> 1;
		for (size_t i = 0; i < hm; i++) {
			fxc s = GM_TAB[m + i];              /* twiddle */
			for (size_t j = j0; j < j0 + ht; j++) {
				fxc x, y;
				x.re = f[j];      x.im = f[j + hn];
				y.re = f[j + ht]; y.im = f[j + ht + hn];
				y = fxc_mul(s, y);
				fxc z1 = fxc_add(x, y);
				f[j] = z1.re; f[j + hn] = z1.im;
				fxc z2 = fxc_sub(x, y);
				f[j + ht] = z2.re; f[j + ht + hn] = z2.im;
			}
			j0 += t;
		}
		t = ht;
	}
}
```

**This is structurally the same (lm, i, j) triple-nested loop shape as
`mp_NTT`'s (lm, u, v)** — `m`/`ht`/`hm` evolve identically, the twiddle
is fetched once per `(lm, i)` pair and reused across the inner `j` loop
exactly like `mp_NTT`'s `s = gm[u+m]` reused across `v`. The difference
is entirely in the per-butterfly arithmetic: `fxc_add`/`fxc_sub` (two
independent 64-bit adds/subs, real and imaginary parts) in place of
`mp_add_f`/`mp_sub_f`, and `fxc_mul` (Karatsuba complex multiply, 3
calls to `fxr_mul` + adds/subs) in place of `mp_montymul` (Montgomery
reduction, also structured as repeated calls to one multiplier — see
`ntt_engine.sv`'s `MM_STEP`, reused 3x per butterfly already).
`vect_iFFT` mirrors `vect_FFT` the same way `mp_iNTT` mirrors `mp_NTT`
(Gentleman-Sande shape, halving via `fxc_half` distributed per-stage —
same "no separate final scaling pass" property already exploited for
`mp_iNTT`).

`vect_mul_fft` (pointwise `fxc_mul` across two FFT-domain vectors) and
`vect_inv_mul2e_fft` (scale-then-invert, `ng_fxp.c:1801`) are simpler
helper passes used once per `babai_loop` iteration around the FFT/iFFT
calls — no address generator needed, just a straight-line pass over the
vector, i.e. cheap to add if the multiplier datapath already exists for
`fxc_mul`.

### What's reusable vs genuinely new

**Reusable (structural):** the address-generator shape (`lm`/`m`/`ht`/
`hm`/`j0` evolution, twiddle-once-per-batch amortization,
`BATCH_INIT`/`LOAD`/`COMPUTE`/`WB` FSM skeleton) maps onto `vect_FFT`/
`vect_iFFT` close enough that reusing `ntt_engine.sv`'s control logic
with a mode bit (NTT-modular-arithmetic vs FFT-complex-fixed-point-
arithmetic) looks realistic — the same unification HawkPU's own
reconfigurable BFU core does for its Sign/Verify-side NTT and FFT.

**Genuinely new:**
- **A 64x64→64 signed fixed-point multiplier** (`fxr_mul`, keeps bits
  [95:32] of the 128-bit product) — different from the existing 32x32
  Montgomery-reduce pipeline (`mm_prod`/`z_q`/`w_q`/`sum_q` in
  `ntt_engine.sv`), and wider. `fxc_mul` needs 3 of these per butterfly
  (same "single multiplier reused 3x" pattern, just a different width).
- **Twiddle table.** `GM_TAB` (`ng_fxp.c:118`) is a **fixed, modulus-
  independent constant table** — 1024 `fxc` entries (128 bits each,
  16KB) of precomputed roots of unity, generated once at compile time,
  not per-call like `gm[]`/`igm[]` (which `mp_mkgm`/`mp_mkgmigm`
  regenerate fresh per NTT call because they depend on the prime in
  use). This is a real simplification opportunity unavailable to the
  NTT engine: since the values never change, this table is a candidate
  for a synthesized ROM/BRAM instead of a DRAM fetch — no `job_gm_addr_i`-
  equivalent needed, no per-job twiddle-table regeneration cost. Whether
  that's worth the ROM area versus just reusing the existing DRAM-fetch
  path is an open question, not decided here.
- Wider staging registers: `fxc` is 128 bits (two 64-bit `fxr` halves)
  versus NTT's 32-bit words — a 16-triple batch (mirroring the current
  `k1_batch_q`/`k2_batch_q` design) would need 16×128×2 = 4096 bits of
  staging per side instead of NTT's 16×32×2 = 1024 bits, a real area
  cost worth weighing against a smaller batch depth.

### Explicitly out of scope here

`poly_sub_scaled`/`poly_sub_scaled_ntt`/`poly_sub_kf_scaled_depth1`
(`ng_poly.c`) are the *other* half of `babai_loop`'s cost, called once
per iteration alongside the FFT/iFFT/mul passes above — but they are
big-integer, multi-word (`Flen`/`flen` words per coefficient, carry-
propagating) scaled-subtraction routines, not a transform. Genuinely
different arithmetic from a fixed-point FFT butterfly; not something
this engine would naturally cover. `babai_loop`'s 2,132,832 cycles are
FFT+mul+subtraction combined, not FFT alone — the FFT-only share within
`babai_loop` has not yet been separately measured and would need its
own profiling pass before sizing the achievable win precisely.

### Status

**Implemented and tested (2026-07-23), decisions made explicitly:**
GM_TAB as a ROM (not DRAM fetch, prioritizing performance over the
one-time area cost), and one shared dual-mode engine (`ntt_engine.sv`
extended in place, not a separate unit) -- "keep on engine only... it
goes at the same speed, and it's cooler to show we shared the unit
between FFT/iFFT and NTT/iNTT."

`keccak_ip/rtl/fft_gm_rom.sv` is a bit-exact extraction of `GM_TAB[1024]`
(1024 `fxc` entries, verified by direct regex extraction from `ng_fxp.c`,
not re-derived) as a synthesizable `localparam` ROM, addressed by the
same `twiddle_idx` the NTT-family address generator already computes.
`ntt_engine.sv`'s "Revision 3" section documents the full derivation:
`job_mode_i` widened to 3 bits (`keccak.hjson`'s `NTT_CTRL.MODE`, `4:2`
now instead of `3:2`); FFT-forward reuses the exact same address-
generator trick as `mp_NTT_autoadj` (`outer_q` starts at 2, `job_logn_i`
= real logn − 1); iFFT needed one additional tweak (`outer_q` starts at
the full `n_q`, not `n_q>>1` like `mp_iNTT`, since iFFT's real
m-sequence is `hn,hn/2,...,2` not `hn/2,hn/4,...,1`) -- both confirmed by
direct derivation against `vect_FFT`/`vect_iFFT`'s C source, not assumed
by analogy. The shared multiplier widened from 32x32->64 (Montgomery) to
64x64->128 (also serving `fxr_mul`'s Q32.32 fixed-point multiply);
NTT-family operands zero-extend into the wider slots, so the low 64
product bits are bit-for-bit identical to the old narrower multiply --
NTT-family behavior is provably unaffected by the width change, confirmed
by rerunning `ntt_engine_test.c` after the change (24/24 still pass, all
four `PRIMES[]`, both directions, plus the 8 autoadj cases).

`fft_engine_test.c` (`vect_FFT`/`vect_iFFT` called directly as the
software reference, same "link and call the real function" approach as
`ntt_engine_test.c`'s `mp_NTT_sw`) passed all 4 correctness cases
(FFT/iFFT x logn=3/8) with **zero mismatches on the first implementation
attempt** -- no debugging cycle needed, unlike the burst-DMA attempt
above. Measured single-operation speedup (hardware vs. the real
`vect_FFT`/`vect_iFFT`, `mcycle`-counted):

| Operation | logn=3 | logn=8 |
|---|---:|---:|
| FFT  | 2.91x (543→186 cyc) | 1.68x (21,649→12,878 cyc) |
| iFFT | 3.70x (483→157 cyc) | 2.16x (24,739→11,408 cyc) |

Notably better than NTT/iNTT's own 1.23x/1.48x single-operation speedup
-- consistent with the ROM twiddle eliminating a DRAM round trip per
batch that NTT-family jobs still pay (`gm[]`/`igm[]` are still DRAM-
fetched, since they're per-modulus and NTT-family can't use a fixed ROM
the way FFT's modulus-independent `GM_TAB` can).

**Wired into the real call sites and KAT-measured (2026-07-23).**
`ng_fxp.c`'s `vect_FFT()`/`vect_iFFT()` are now transparent dispatchers
(same pattern as `mp_NTT`/`mp_iNTT` in `ng_mp31.c`: renamed originals to
`vect_FFT_sw`/`vect_iFFT_sw`, external linkage, called directly by
`fft_engine_test.c` to keep that test a genuine hw-vs-sw comparison and
not accidentally hw-vs-hw). Every real caller redirects for free:
`ng_hawk.c`'s KeyGen constant-term check and `ng_ntru.c`'s `babai_loop`
(`solve_NTRU_intermediate`) and `solve_NTRU_depth0`. `f` is staged
through a fourth non-cacheable DRAM scratch window
(`FFT_HW_SCRATCH_ADDR = 0x80F01000`, distinct from `GAUSS_HW_SCRATCH_ADDR`/
the two existing `NTT_HW_SCRATCH_ADDR` windows), same convention as
`mp_NTT_hw`. `hawk_vrfy.c`'s Verify path was deliberately left untouched
-- it uses a structurally different function, `fx32_FFT` (32-bit
fixed-point, not `ng_fxp.c`'s 64-bit `fxr`/`fxc`), not `vect_FFT`, so this
engine doesn't apply there without a separate analysis.

Full KAT (`Keygen OK`/`Sign OK`/`Verify OK`), `fft_dispatch_cycles`
accounting added to `main.c` (same pattern as `ntt_dispatch_cycles`):

| Phase | Before FFT wiring | After FFT wiring | Change |
|---|---:|---:|---:|
| KeyGen | 7,786,426 | **7,707,400** | **−1.0%** (79,026 cycles) |
| Sign | 323,507 | 326,247 | noise (Sign never calls `vect_FFT`) |
| Verify | 439,096 | 442,453 | noise (`fx32_FFT` is untouched by this work) |

**The honest result: real, but modest.** 396 `vect_FFT`/`vect_iFFT` calls
now cost 283,902 hardware cycles total (3.6% of KeyGen) instead of
whatever larger software cost they used to take -- that's where the
79,026-cycle KeyGen saving comes from, and it's consistent with the
1.68x-3.7x per-call speedup measured above. But `babai_loop`'s own
measured cost only dropped 2,132,832 -> 2,086,243 cycles (a 2.2%
reduction in the loop, not close to the 27.3%-of-KeyGen this loop as a
whole represents), because `poly_sub_scaled`/`poly_sub_scaled_ntt`/
`poly_sub_kf_scaled_depth1` -- the loop's *other* half, still 100%
software -- was never touched and turns out to dominate `babai_loop`'s
total cost far more than the FFT/iFFT transform itself does. This
confirms, with real numbers instead of an open question, the caveat
flagged before this pass: FFT/iFFT was never going to be the majority of
`babai_loop`'s cost on its own. If KeyGen is revisited again, the
big-integer `poly_sub_scaled` family (scoped but explicitly declined
earlier in favor of this FFT work) is the next concrete candidate, now
with a firmer number backing why it matters more than it first looked --
`babai_loop` is still 27% of KeyGen after this change, and FFT/iFFT was
only ever one of its two halves.

### How to run these tests

Both are standalone hardware-vs-software correctness (+ speedup, for the
FFT one) tests, run from the `cva6/` repository root:

```
bash tests/hawk-256-keccak/run_ntt_engine_test.sh   # mp_NTT/mp_iNTT/autoadj, ~3 min
bash tests/hawk-256-keccak/run_fft_engine_test.sh   # vect_FFT/vect_iFFT, ~3 min
```

Source: `tests/hawk-256-keccak/ntt_engine_test.c` / `fft_engine_test.c`
(both call the real software reference directly -- `mp_NTT_sw`/`mp_iNTT_sw`
and `vect_FFT_sw`/`vect_iFFT_sw` respectively -- bypassing the hardware
dispatchers so the comparison is genuine hw-vs-sw, not hw-vs-hw). Output
goes to the simulated UART; look for `OK (0 mismatches)` per case and,
for the FFT test, a `speedup=` line per case. To see the full KAT-wide
impact (KeyGen/Sign/Verify total cycles, plus the `mp_NTT`/`vect_FFT`
dispatch-cycle breakdowns tables above are drawn from):

```
bash tests/hawk-256-keccak/run.sh   # ~9-10 min
```
