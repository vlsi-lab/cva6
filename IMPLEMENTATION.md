# vrf_ip — implementation notes

This document consolidates the design/implementation notes previously spread
across `NTT_ACCEL_DESIGN.md` and the per-scheme `README.md` files under
`tests/{vrf,pqc}/optimized/falcon{512,1024}/`. Those files are superseded by
this one and have been removed. For measured results (cycle counts,
speedups, KAT status) see `results.md`; this document covers architecture,
design rationale, and decisions made along the way (including attempts that
were reverted).

## Architecture

`vrf_ip` is a single memory-mapped AXI peripheral (`vrf_ip/rtl/vrf_axi_top.sv`,
base address `0x5000_0000`, registers generated from `vrf_ip/vrf.hjson` via
`vrf_ip/sw/vrf_axi.h`) shared by Falcon, ML-DSA, and SPHINCS+/SLH-DSA verify.
It is **loosely coupled**: an ordinary MMIO/DMA peripheral on CVA6's AXI bus,
not a CV-X-IF custom-instruction coprocessor (CVA6 has a dormant CV-X-IF port,
`cvxif_req_o`/`cvxif_resp_i` in `cva6.sv`, tied to a stub in `ariane.sv` —
deliberately not used here).

One shared Keccak-f[1600] core (`keccak_f.sv`/`keccak_round.sv`/`keccak_dp.sv`/
`keccak_cu.sv`, 1600-bit on-chip state register, `pkg_keccak.sv`) serves every
scheme's hashing needs through several job front-ends, all muxed onto one
physical AXI master port in `vrf_axi_top.sv` (mutually exclusive `busy_o`
signals select which front-end drives the shared port; no job type runs
concurrently with another by construction — a verify sequences its jobs
serially):

| Front-end | File | Purpose |
|---|---|---|
| DMA-absorb / CSREG raw-permute | `keccak_dma_ctrl.sv` | Multi-block SHAKE/SHA3 absorb straight from DRAM; raw Keccak-f permute for single-block/incremental use |
| NTT/iNTT | `ntt_engine.sv` | Number-theoretic transform (Falcon q=12289, ML-DSA q=8380417 — any prime, not hardcoded) |
| Rejection sampler | `rej_sampler.sv` | Falcon `hash_to_point_vartime`, ML-DSA `rej_uniform` |
| SPHINCS+ hash-chain | `chain_job_ctrl.sv` | WOTS+ chain steps, FORS/Merkle THASH1/THASH2, PRF_ADDR |
| Falcon signature decompression | `falcon_decode.sv` | `Zf(comp_decode)()` — Falcon-specific, no cross-scheme shape to share |
| Falcon norm/bound check | `falcon_normcheck.sv` | `Zf(is_short)()` — Falcon-specific, no cross-scheme shape to share |

## Design principles followed throughout

- **Area minimization is the top priority** (explicit project direction).
  Every addition was weighed against reuse of existing datapaths before
  adding new ones; see "Reuse decisions" below for cases where reuse was
  considered and rejected, and why.
- **Cross-scheme sharing wherever the algorithms' shapes actually match.**
  `ntt_engine.sv`, `rej_sampler.sv`, and the Keccak core are shared verbatim
  by multiple schemes at zero extra area cost (same RTL instance either way).
  Where shapes don't match (Falcon's decompression/norm-check vs. ML-DSA's
  fixed-width packing / max-abs norm check), scheme-specific modules were
  built instead of forcing an ill-fitting shared design.
- **Measure before keeping.** Two on-chip-buffering attempts
  (`rej_sampler.sv`, and `ntt_engine.sv`'s VECMUL/VECSUB job modes) were
  built, validated for correctness, and then reverted after real RTL
  measurement showed a net cycle regression on the full verify path. Passing
  correctness is not sufficient justification to keep a change — see
  "Reuse decisions" below.
- **Every primitive gets a standalone SW-vs-HW test before wiring into real
  algorithm code**, mirroring the reference implementation (or a
  from-scratch software reference derived independently, so a hardware bug
  and a copy-pasted software bug can't both produce a false pass) rather
  than trusting integration-level KAT pass/fail alone to catch primitive
  bugs. See `tests/app-tests/*` for the current set.

## Non-cacheable scratch-window convention

This SoC's `DcacheFlushOnFence`/`DcacheInvalidateOnFlush` are both `0`
(`core/include/cv64a6_imac_crypto_config_pkg.sv`), so a plain `fence` does
not flush or invalidate the CPU's D$. This matters in exactly one direction:

- **Accelerator reads an input the CPU just wrote** (e.g. a job's source
  array): a plain `fence` before dispatch is sufficient — it orders the
  CPU's own writes ahead of the accelerator's read, same as any ordinary
  MMIO/DMA producer-consumer sequencing.
- **Accelerator writes a result the CPU will later read** (e.g. a job's
  output array, DMA-written by the accelerator's own AXI master): a plain
  `fence` does **not** invalidate any D$ line the CPU may have already
  cached for that address, so a later CPU read can silently return stale
  data if the CPU had touched that address before.

The fix used everywhere in this codebase: dedicate a small, genuinely
non-cacheable DRAM window for HW-written output
(`CachedRegionLength` in `cv64a6_imac_crypto_config_pkg.sv` leaves
`0x80F0_0000`-`0xC000_0000` uncached specifically for this), write results
there, then copy out to the caller's real buffer via an ordinary software
loop (which correctly populates the D$ as it goes). Established addresses:
`VRF_NTT_HW_SCRATCH_ADDR = 0x80F09000`, `VRF_REJ_HW_SCRATCH_ADDR =
0x80F0A000`, `VRF_DECODE_HW_SCRATCH_ADDR = 0x80F0B000`. This was found the
hard way twice — once during `ntt_engine.sv`'s original integration, and
again during `falcon_decode.sv`'s bring-up (see "Bugs found" below) — so it
is now applied proactively to every new HW-output-producing job without
waiting to hit the symptom again.

## On-chip working-buffer pattern (`ntt_engine.sv`, Item 1) — and where it does/doesn't pay off

`ntt_engine.sv` originally issued one single-outstanding DRAM transaction per
operand, per butterfly — for an `n`-stage NTT this touches every coefficient
`~logn` times (once per stage), which measurement (`ntt_hw_cost_breakdown.c`)
showed was ~87% of a single NTT call's cycles. The fix: a small on-chip
array (`a_buf`, 1024×32-bit = 4KB, sized for the largest N in use across all
schemes sharing the engine — Falcon-1024) holds the whole coefficient array
for one job's duration. `BULK_LOAD`/`BULK_STORE` phases move the array to/
from DRAM once, at job start/end (still single-outstanding — burst DMA was
attempted and abandoned, see "Reuse decisions" below); every per-stage
read-modify-write during the transform then hits the on-chip buffer instead
(1-cycle synchronous access, no bus handshake). Real bug found during
bring-up: `BULK_STORE`'s first attempt read the on-chip buffer's registered
output directly while waiting (possibly several cycles) for `mem_gnt_i`;
since only the read state itself drove the buffer's read address, every
extra wait cycle silently re-latched address 0's value. Fixed by adding an
explicit capture register in an intermediate single-cycle state before
entering the wait-prone request state — a pattern now applied preemptively
to every new on-chip-buffer design in this codebase.

**This pattern is a genuine win only when a value is read/written from DRAM
redundantly multiple times per job** (NTT's ~logn-times-per-coefficient
traffic is exactly that shape). It was tried twice more for jobs that only
touch each DRAM word once, and lost both times:

- `rej_sampler.sv`: deferring per-accepted-candidate DRAM writes to an
  end-of-job flush measured *worse* (1,559 → 1,749 cycles on the
  `rej-mldsa` app-test) — ML-DSA/Falcon's high acceptance rates (>99.8%
  for ML-DSA) mean there's little squeeze work between accepts for
  deferred writes to overlap with, so the buffered design's own
  write-then-read-back tax has nothing to offset it. Reverted.
- `ntt_engine.sv` VECMUL/VECSUB (an attempt to offload Falcon's
  `mq_poly_montymul_ntt`/`mq_poly_sub`): measured worse on the full
  falcon512 KAT (198,962 → 220,736 verify cycles, ~11% regression).
  Root cause: unlike NTT's butterflies, a pointwise multiply/subtract
  touches each element exactly once regardless of design, so there is no
  redundant DRAM traffic for on-chip buffering to remove — only the
  scratch-relay software copy's own overhead (~2×n slow non-cacheable MMIO
  accesses per call) to add, with nothing to amortize it against. Built,
  validated bit-exact on real RTL (8/8 standalone cases across two primes,
  three sizes, and the n=1 edge case), wired into `vrfy.c`, measured, and
  reverted in full (RTL, register map, software) once the regression was
  confirmed reproducible after a clean rebuild.

Net lesson: this accelerator's per-transaction DRAM latency is the
dominant cost for *any* job shape, and on-chip buffering only helps when it
removes *repeated* redundant traffic, not merely relocates a fixed amount
of it through an extra hop.

## Reuse decisions (multiplier/datapath sharing considered and rejected)

- **Falcon norm-check (`falcon_normcheck.sv`, Item 6) vs. reusing
  `ntt_engine.sv`'s multiplier.** `Zf(is_short)()`'s squaring is a *plain*
  (unreduced) integer operation on signed 16-bit coefficients — structurally
  unlike `ntt_engine.sv`'s 32-bit Montgomery-domain butterfly multiply.
  Routing this job's much simpler operation through that FSM's addressing/
  control logic was judged likely to cost more in mux/control overhead than
  a small dedicated 17×17 signed squarer costs on its own, so
  `falcon_normcheck.sv` uses its own minimal squarer instead.
- **Burst/wide AXI DMA** (`ntt_engine.sv`, pre-Item-1 history): a 16-lane
  `CACHE_LINE_REQ` burst was implemented to cut per-word DRAM round-trip
  count directly, reusing `axi_adapter.sv` rather than building a dedicated
  burst master. Abandoned after real RTL simulation showed
  `axi_adapter.sv`'s burst read path unconditionally zeroes the low
  `CACHELINE_BYTE_OFFSET` address bits (built for CVA6's own cache-line-
  aligned dcache/icache fetches, not arbitrary-offset block transfers) —
  this silently corrupted non-cache-aligned batch addresses. Fixing it
  properly would mean either constraining the batching scheme to
  cache-line-aligned addresses (uncertain hit rate against the actual
  access pattern) or building a genuinely dedicated burst master (real new
  RTL/verification surface) — both judged not worth it against the
  "smallest hardware possible" priority. What *did* ship from that work:
  batching up to 16 consecutive butterflies' shared twiddle fetch into one
  round trip (still single-outstanding, but amortizes the twiddle fetch,
  not the `a[]`/`k1`/`k2` traffic — that needed Item 1's on-chip buffer
  instead).
- **Pipelined multiple-outstanding reads** (considered as a burst
  alternative): also blocked — `axi_adapter.sv`'s read path is
  single-outstanding by construction (`WAIT_R_VALID` is singular; no
  outstanding-read counter exists, unlike the write path's
  `outstanding_aw_cnt_q`). Reopening either the burst or multi-outstanding
  path touches shared, correctness-critical core RTL used by the CPU's own
  LSU — not pursued.

## Falcon-specific integration notes

- **SHAKE256 hardware-resident-state dispatch** (`shake.c`): every
  `Zf(i_shake256_init/inject/flip/extract)` call site keeps its original
  function name/signature; each is a transparent dispatcher to the shared
  Keccak core, tracked via a `hw_owner`/`hw_seen` residency flag so
  interleaved use by different logical contexts (e.g. a KeyGen RNG context
  vs. a Verify hash-to-point context) evicts/re-uploads correctly regardless
  of call order. Falcon verify's hash-to-point loop
  (`Zf(hash_to_point_vartime)`) squeezes on the order of ~550 two-byte
  values per Falcon-512 verify from one absorbed state; with residency, only
  the ~8 calls that actually cross a 136-byte rate boundary trigger a real
  Keccak-f permutation — every other extract is a pure register readback.
- **NTT/iNTT domain mismatch**: `ntt_engine.sv`'s Montgomery reduction uses
  its own R=2^32 convention; Falcon's native `mq_montymul()` (`vrfy.c`) uses
  a different, bespoke R=2^16 reduction (`GMb`/`iGMb`/`R2=10952`). Reusing
  the engine for Falcon's `q=12289` required a *separate*, purpose-generated
  x2^32-Montgomery twiddle table (`GM32[]`/`iGM32[]`, via the engine's own
  `mp_mkgmigm()` helper, encoding Falcon's own primitive root `g=7`) — not
  simply pointing the existing tables at new registers. The payoff: since
  only the twiddle table itself carries the Montgomery R factor (the
  transform is domain-*preserving* — plain input in, plain NTT out,
  regardless of which Montgomery convention the twiddles/reduction use
  internally), the surrounding glue
  (`mq_poly_tomonty`/`mq_poly_montymul_ntt`/`mq_poly_sub`) needed **zero
  changes** and still runs Falcon's native 16-bit domain exactly as the
  reference does. This is also why the VECMUL/VECSUB attempt above (which
  *would* have needed to bridge the two domains, via a software-computed
  `R32SQ_MODQ` pre-scaling constant) added real complexity beyond "just
  reuse the multiplier" — a complexity that turned out moot once the
  approach was reverted for performance reasons anyway.
- **Rejection sampler** (`rej_sampler.sv`, via `Zf(hash_to_point_hw)()` in
  `shake.c`): per-word datapath compares each squeezed 16-bit big-endian
  word against a per-job `thresh` register (61445 = 5×12289 for Falcon);
  rejects squeeze again (no output, matching the reference's "vartime"
  variable-length behavior); accepts reduce mod `q` via a fixed 4-stage
  conditional-subtract chain (exact since `61444/12289 < 5`). `q`/`thresh`/
  `n` are plain per-job registers, not hardwired to Falcon's values, so
  ML-DSA's `rej_uniform` reuses the same RTL instance with its own modulus.
- **Signature decompression** (`falcon_decode.sv`, Item 5): bit-serial
  Golomb-Rice-style decode (1 sign bit + 7 low magnitude bits, possibly
  starting mid-byte, + unary-coded high part) with malformed-input rejection
  matching `Zf(comp_decode)()`'s exact `return 0` conditions (unary run
  >2047, forbidden "-0", input exhausted early, nonzero trailing bits).
  Reads the input stream one byte at a time directly via the shared AXI
  master (not word-cached) — decompression is small/bounded relative to
  NTT/matrix-expansion work, so moving the bit-level shift/mask/branch work
  into hardware is a real win even without reducing DRAM transaction count.
- **Norm/bound check** (`falcon_normcheck.sv`, Item 6): accumulates
  `sum(s1[u]^2) + sum(s2[u]^2)` with the reference's own constant-time
  saturating-overflow trick (`ng |= s` after every add; final
  `s |= -(ng>>31)` forces the sum to all-1s if it ever exceeded `2^31-1`),
  simplified to a single sticky overflow bit (mathematically equivalent,
  since OR is monotonic and only bit 31 of the reference's accumulator is
  ever read back). Always walks all `n` coefficients of both arrays before
  comparing against the bound — preserving the reference's constant-time
  property (no early exit that would leak how far over/under the bound the
  norm is).

## Bugs found during bring-up (real RTL, not caught by static review)

- **`ntt_engine.sv` (Item 1)**: first RTL run showed 511/512 coefficients
  wrong, all showing the *same* wrong value — the "all mismatches show one
  fixed value" signature pointed directly at a stale-address read rather
  than a general logic error (see "On-chip working-buffer pattern" above).
- **`falcon_decode.sv` (Item 5) test harness**: first standalone-test run
  showed the *first* dispatch pass but every subsequent one fail, each
  showing the *previous* call's own values — the D-cache-staleness pattern
  described above, isolated via a minimal two-call repro before the fix
  (route output through a non-cacheable scratch window) was applied.
- **Verilator/Make incremental-build staleness** (process note, not an RTL
  bug): after reverting the VECMUL/VECSUB change, a re-run of the full KAT
  reused a stale pre-revert simulation binary (`make[2]: Nothing to be done
  for 'default'`) despite the RTL source having changed, giving a
  misleading "still regressed" reading. A `rm -rf work-ver` before the next
  run forced a clean rebuild and confirmed the revert was correct. Worth
  doing before trusting any RTL-dependent measurement after a source change
  that doesn't also touch `Flist.cva6`'s file list.

## Area synthesis flow (`corev_apu/fpga/synth_area/`)

Real Vivado out-of-context synthesis (no bitstream, no place & route),
adapted from a sibling repository's own proven CW305-targeted area flow.
See `results.md`'s "Area" section for the actual numbers; this section
covers the flow itself and two findings made while building it.

- `rtl/vrf_synth_top.sv`: the synthesis top, instantiating `ariane` (CVA6
  core) and `vrf_axi_top` (the whole accelerator) as two independent
  sibling instances with plain top-level ports, rather than through a real
  SoC crossbar/DDR controller — sufficient for area attribution, since
  Vivado's OOC mode counts each instance's own internal logic regardless
  of what (if anything) drives its top-level ports.
- `scripts/run_synth.tcl`: parses `core/Flist.cva6` directly (the same
  "core-only" manifest, already including every `vrf_ip/rtl/*.sv` file, so
  no extra entries were needed for the accelerator itself) rather than
  maintaining a hand-written duplicate file list. Building this surfaced a
  real gap in `core/Flist.cva6`: `corev_apu/register_interface/src/
  axi_to_reg.sv` (which `vrf_axi_top` uses for its register bus, and which
  `core/Flist.cva6` does list) pulls in a further dependency chain
  (`axi_to_axi_lite.sv` → `axi_atop_filter.sv`/`axi_burst_splitter.sv` →
  `stream_register.sv` → `fifo_v2.sv`) that the core-only manifest never
  anticipated, since nothing inside `ariane`/`cva6` itself needs it. Found
  one file at a time via four successive real Vivado elaboration failures
  ("module X not found"), not predicted — the script now bundles whole
  `vendor/pulp-platform/{axi,common_cells}/src` directories (and
  `common_cells/src/deprecated`), de-duplicated by basename against what
  `core/Flist.cva6` already provides, rather than continuing to chase
  individual files one at a time.
- **`corev_apu/fpga/src/ariane_xilinx.sv` (the real FPGA top used for
  other boards, e.g. genesys2/vc707) never wires `vrf_axi_top`'s DMA
  master port (`dma_req_o`/`dma_addr_o`/etc.) to anything at all** — found
  while cross-checking `vrf_synth_top.sv`'s own port list against the real
  integration. Only `corev_apu/tb/ariane_testharness.sv` (the RTL
  simulation testbench used throughout this whole project's validation)
  wires it correctly, through a separate `axi_adapter` instance. This is a
  real gap for anyone building an actual bootable/flashable bitstream for
  genesys2/vc707/etc — the accelerator's own DMA master port would be
  dangling on real hardware today. Not a concern for the area-only
  synthesis flow itself (which doesn't need a working interconnect), but
  worth fixing before any real board bring-up.
- Usage: `cd corev_apu/fpga/synth_area && ./run_synth.sh` (defaults: CW305
  part `xc7a100tftg256-2`, 100 MHz virtual clock — override via
  `XILINX_PART=... CLK_PERIOD_NS=... ./run_synth.sh`), then
  `python3 scripts/report_area.py` to extract the per-block breakdown into
  `reports/area_summary.md`.

## Verification workflow

Every new job front-end followed the same sequence:

1. Read the reference C implementation directly (never re-derived from
   memory) and cross-check any non-obvious index/domain arithmetic against
   it explicitly.
2. Build a standalone `tests/app-tests/<name>` test comparing hardware
   output against an independently-derived software reference (not a
   copy-paste of the reference being accelerated, so a shared bug can't
   produce a false pass), covering the happy path, boundary values, and
   malformed/edge-case inputs where relevant.
3. Run on real `veri-testharness` RTL simulation (Verilator) — never trust
   compile-clean or native-host cross-checks alone for a hardware-facing
   change.
4. Wire into the real algorithm source (`tests/vrf/optimized/<scheme>/*.c`),
   keeping the accelerated function's name/signature identical to the
   original so call sites need no change.
5. Re-run the full KAT for every affected scheme/variant on real RTL and
   confirm both `*** SUCCESS ***` and a recorded cycle count.
6. If a change's expected benefit doesn't materialize (regression despite
   correctness), revert it fully and record why — see "On-chip
   working-buffer pattern" above.