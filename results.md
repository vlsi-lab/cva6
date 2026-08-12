# vrf_ip — results summary

`vrf_ip` is a memory-mapped AXI hardware accelerator (loosely coupled, not
CV-X-IF) shared by Falcon, ML-DSA, and SPHINCS+/SLH-DSA **verify** on CVA6.
This document summarizes where the project stands: measured results, what
has been validated, what remains possible, and the accelerator's area
footprint. For architecture and design-decision detail, see
`IMPLEMENTATION.md`.

All cycle counts are the RISC-V `mcycle` CSR delta for the `verify` phase
only, measured on real RTL (Verilator `veri-testharness`, `cv64a6_imac_crypto`
target), single KAT vector per run (`N_KAT=1`), not averaged across multiple
vectors.

## Results — cycle counts and speedup vs. software baseline

| Scheme | SW baseline (cycles) | HW-accelerated (cycles) | Speedup | KAT status |
| --- | ---: | ---: | ---: | :--- |
| Falcon-512 | 473,731 | 198,962 | **2.38×** | `*** SUCCESS ***` |
| Falcon-1024 | 989,155 | 412,274 | **2.40×** | `*** SUCCESS ***` |
| ML-DSA-44 | 1,504,523 | 754,996 | **1.99×** | `*** SUCCESS ***` |
| ML-DSA-65 | 2,413,716 | 1,147,958 | **2.10×** | `*** SUCCESS ***` |
| ML-DSA-87 | 3,941,622 | 1,786,458 | **2.21×** | `*** SUCCESS ***` |

All 11 schemes / 22 variants (Falcon-{512,1024}, ML-DSA-{44,65,87},
SPHINCS-{128f,192f,256f}-{robust,simple}) pass their KAT with hardware
acceleration enabled. SPHINCS+/SLH-DSA speedup vs. a software baseline is
not reported here because a clean software-only baseline was never
separately re-collected for those 6 variants after the hash-chain
accelerator (`chain_job_ctrl.sv`) was wired in — only cycle counts and
cumulative reductions across phases are available (below). Reporting a
speedup number without a baseline actually measured under the same
conditions would not be trustworthy.

| SPHINCS+/SLH-DSA variant | HW-accelerated (cycles) | KAT status |
| --- | ---: | :--- |
| SPHINCS-128f-robust | 1,065,694 | `*** SUCCESS ***` |
| SPHINCS-128f-simple | 508,479 | `*** SUCCESS ***` |
| SPHINCS-192f-robust | 1,671,336 | `*** SUCCESS ***` |
| SPHINCS-192f-simple | 745,913 | `*** SUCCESS ***` |
| SPHINCS-256f-robust | 1,960,733 | `*** SUCCESS ***` |
| SPHINCS-256f-simple | 811,244 | `*** SUCCESS ***` |

> Speedup definition: baseline cycles ÷ accelerated cycles. Source logs for
> each measurement live under `verif/sim/out_<date>/veri-testharness_sim/`.

## What has been accelerated

- **Keccak-f[1600] permutation**, shared by all three schemes, via a single
  on-chip core with two dispatch modes: raw single-permute (CSREG/DATA[])
  and autonomous multi-block DMA-absorb straight from DRAM.
- **NTT/iNTT** (Falcon `q=12289`, ML-DSA `q=8380417`) — one generic
  32-bit-domain Montgomery engine, any prime supplied per-job (not
  hardcoded), shared by both schemes' verify paths.
- **Rejection sampling** — Falcon's `hash_to_point_vartime`, ML-DSA's
  `rej_uniform`, one shared engine.
- **SPHINCS+/SLH-DSA hash-chain steps** — WOTS+ chain, FORS/Merkle
  THASH1/THASH2, PRF_ADDR.
- **Falcon signature decompression** (`Zf(comp_decode)`) — Falcon-specific.
- **Falcon norm/bound check** (`Zf(is_short)`) — Falcon-specific.

Every item above has: a standalone hardware-vs-independently-derived-
software-reference test under `tests/app-tests/`, real-RTL validation, and
a full KAT re-check on every scheme/variant it affects after being wired
into the real algorithm source. See `IMPLEMENTATION.md`'s "Verification
workflow" section.

## What was tried and did not pay off (reverted, not shipped)

Two on-chip-buffering attempts were built, correctness-validated on real
RTL, and then reverted after full-KAT measurement showed a net cycle
*regression* rather than the expected improvement:

- **`rej_sampler.sv` output buffering** (defer per-accepted-candidate DRAM
  writes to an end-of-job flush): 1,559 → 1,749 cycles on the `rej-mldsa`
  standalone benchmark (~12% worse).
- **`ntt_engine.sv` VECMUL/VECSUB job modes** (offload Falcon's
  `mq_poly_montymul_ntt`/`mq_poly_sub` pointwise steps): 198,962 → 220,736
  verify cycles on the full falcon512 KAT (~11% worse).

Both share a root cause: the on-chip-buffer pattern that gave Item 1's NTT
work a real win only pays off when a value is read/written from DRAM
*redundantly multiple times* per job (NTT's per-stage traffic). Jobs that
touch each DRAM word exactly once regardless of design have no redundant
traffic for on-chip buffering to remove — only the scratch-relay software
copy's own overhead to add. See `IMPLEMENTATION.md` for the full writeup
of both attempts, including the VECMUL/VECSUB root-cause analysis.

## What is missing / could still be done

Not exhaustive — a list of explicitly-identified, not-yet-closed gaps:

- **Falcon's `mq_poly_montymul_ntt`/`mq_poly_sub` pointwise steps** remain
  software (native 16-bit-domain `mq_montymul`), per the revert above. No
  currently-understood design closes this gap without adding more overhead
  than it removes in this loosely-coupled architecture; would need a
  genuinely different approach (e.g. a job shape that amortizes fixed
  per-dispatch cost across more work per dispatch) to be worth revisiting.
- **ML-DSA's incremental multi-call `shake256_absorb()` sequences**
  (transcript hash, challenge derivation — 2-3 separate calls building up
  one context) are not coalesced into a single DMA job; only the single
  non-incremental `shake256(mu, ...)` pk-hash call was re-pointed at the
  DMA-absorb job. Closing this would need either a pre-dispatch
  concatenation copy (uncertain net win) or extending `keccak_dma_ctrl.sv`
  to accept multiple discontiguous input segments in one job (real new
  RTL).
- **No software baseline for SPHINCS+/SLH-DSA** was collected under the
  same measurement conditions as the accelerated numbers, so no speedup
  figure can be honestly reported for those 6 variants (see the results
  table above) — only cycle counts and cross-phase reductions are
  available today.
- **Only out-of-context synthesis has been run** (Vivado, area/timing
  estimate only) — no place & route, no timing closure, no bitstream; see
  "Area" below for the real numbers and their caveats.
- **The AXI-to-register-bus bridge (`axi_to_reg`) is 16.4% of `vrf_ip`'s
  own area** — larger than 6 of the 8 job front-ends combined. Not
  something identified before this session's synthesis run; worth a closer
  look in a future pass (e.g. whether its `AxiMaxWriteTxns`/
  `AxiMaxReadTxns` parameters or ID-width handling can be trimmed for this
  accelerator's actual traffic pattern — single-outstanding, one master).
- **`ariane_xilinx.sv` (the FPGA top for boards other than the synthesis-
  only CW305 flow added this session) never wires `vrf_axi_top`'s DMA
  master port to anything** — a real gap for an actual bootable/flashable
  build on genesys2/vc707/etc, found while building the area-synthesis
  flow (see `IMPLEMENTATION.md`). Only the simulation testbench
  (`ariane_testharness.sv`) wires it correctly today.
- **Falcon-1024's baseline** (989,155 cycles) is carried from an earlier
  measurement rather than freshly re-verified alongside every later change
  in this session; the other four numbers in the top results table were
  all freshly re-measured this session.

## Area

Real Vivado 2024.1 out-of-context synthesis (`synth_design -mode
out_of_context`, no place & route, no bitstream — see
`corev_apu/fpga/synth_area/`), targeting the CW305's part
(`xc7a100tftg256-2`, Artix-7 100T) with a 100 MHz virtual clock on `clk_i`
(not timing-critical — this run is for area only). The synthesis top
(`vrf_synth_top.sv`) instantiates `ariane` (the CVA6 core) and
`vrf_axi_top` (the whole accelerator) as two independent sibling
instances, each exposed via plain top-level ports rather than wired
through a real SoC crossbar/DDR controller — sufficient for a per-instance
area report, since Vivado's OOC synthesis counts each instance's internal
logic independent of what drives its top-level ports. See
`IMPLEMENTATION.md` for why this design was chosen over the (broken, in
the sibling repo this flow was adapted from) full board-bitstream flow.
Full breakdown: `corev_apu/fpga/synth_area/reports/area_summary.md`
(regenerate with `./run_synth.sh && python3 scripts/report_area.py` from
that directory).

| Block | Total LUTs | FFs | RAMB36 | DSP | % of vrf_ip LUTs |
| --- | ---: | ---: | ---: | ---: | ---: |
| **Whole system** (`vrf_synth_top`) | 70,402 | 33,577 | 37 | 33 | — |
| **CVA6 core** (`i_ariane`) | 52,966 | 23,607 | 36 | 27 | — |
| **vrf_ip, whole** (`i_vrf_axi_top`) | **17,436** | **9,969** | **1** | **6** | 100% |
| — shared Keccak-f[1600] core | 6,295 | 1,631 | 0 | 0 | 36.1% |
| — SPHINCS+/SLH-DSA hash-chain job | 3,391 | 1,587 | 0 | 0 | 19.4% |
| — AXI-to-register-bus bridge | 2,853 | 672 | 0 | 0 | 16.4% |
| — NTT/iNTT job (Falcon + ML-DSA) | 1,723 | 1,690 | 1 | 4 | 9.9% |
| — register file | 1,680 | 3,552 | 0 | 0 | 9.6% |
| — rejection sampler (Falcon + ML-DSA) | 424 | 215 | 0 | 0 | 2.4% |
| — DMA-absorb/CSREG job | 510 | 149 | 0 | 0 | 2.9% |
| — Falcon norm/bound check | 283 | 230 | 0 | 2 | 1.6% |
| — Falcon signature decompression | 277 | 241 | 0 | 0 | 1.6% |

`vrf_ip` is **24.8% of system Total LUTs, 29.7% of system FFs** — the CVA6
core alone accounts for the remaining ~75%/70%. Within `vrf_ip`, the
shared Keccak-f[1600] core is the single largest block (36.1% of the
accelerator's own LUTs) — expected, and a good area investment precisely
*because* it's shared by every scheme's hashing needs rather than
duplicated. The **AXI-to-register-bus bridge (`axi_to_reg`) at 16.4% is a
real, actionable finding**: it's larger than 6 of the 8 job front-ends
combined (decode + normcheck + rej_sampler + DMA-absorb job = 1,494 LUTs
vs. 2,853), and is fixed protocol-conversion overhead that doesn't scale
with functionality — meaning it becomes proportionally *cheaper* as more
capability is added to `vrf_ip` (an argument for keeping everything on one
shared accelerator rather than splitting into several smaller ones, each
paying this bridge cost separately), but on its own, today, it is the
second-largest single block in the design. SPHINCS+'s hash-chain job
(19.4%) is the largest single-scheme-specific block — expected, since it's
the only job front-end serving just one of the three schemes at this
scale (Falcon's decompression/norm-check are comparably small, 1.6% each,
by design).

**Caveats**: this is a synthesis-only, out-of-context result — no place &
route, no timing closure, no bitstream, and the accelerator's DMA master
port (`dma_req_o` etc.) is exposed as plain dangling top-level ports here
rather than routed through a real interconnect (see `IMPLEMENTATION.md`'s
note that `corev_apu/fpga/src/ariane_xilinx.sv`, the real FPGA top for
other boards, has this same gap — it was never wired there either, only
the simulation testbench wires it correctly). Absolute LUT/FF counts from
an OOC run can differ from a fully-placed, timing-closed design (Vivado
may not apply the same optimizations without full-context visibility), so
treat these as directionally accurate, not final sign-off numbers.

**On-chip storage** (unchanged from RTL-level inspection, and consistent
with the BRAM/DSP counts above):

| Block | Size | Shared across |
| --- | ---: | --- |
| Keccak-f[1600] state register (`keccak_dp.sv`) | 1,600 bits (200 B) | All 3 schemes, every job front-end that hashes |
| `ntt_engine.sv` on-chip working buffer (`a_buf`) | 1024 × 32 bits (4 KB) | Falcon + ML-DSA (both NTT/iNTT users) |

No other job front-end (`rej_sampler.sv`, `falcon_decode.sv`,
`falcon_normcheck.sv`, `chain_job_ctrl.sv`) holds an on-chip buffer — each
streams its operands directly to/from DRAM one word at a time by design
(see `IMPLEMENTATION.md`'s on-chip-buffer section for why this was the
right call for those job shapes specifically).

**RTL line counts** (a rough complexity proxy only — not proportional to
gate count):

| File | Lines | Role |
| --- | ---: | --- |
| `ntt_engine.sv` | 734 | NTT/iNTT + on-chip buffer (Falcon, ML-DSA) |
| `chain_job_ctrl.sv` | 482 | SPHINCS+/SLH-DSA hash-chain |
| `vrf_axi_top.sv` | 468 | Top-level register file + job-front-end mux |
| `rej_sampler.sv` | 386 | Rejection sampling (Falcon, ML-DSA) |
| `falcon_decode.sv` | 341 | Falcon signature decompression |
| `keccak_dma_ctrl.sv` | 274 | Multi-block DMA absorb/squeeze |
| `falcon_normcheck.sv` | 239 | Falcon norm/bound check |
| `keccak_round.sv` | 185 | Keccak-f[1600] round logic |
| `keccak_dp.sv` | 129 | Keccak datapath + state register |
| `keccak_cu.sv` | 90 | Keccak control unit |
| `keccak_round_constants_gen.sv` | 72 | Keccak round-constant generation |
| `pkg_keccak.sv` | 55 | Shared type/constant definitions |
| `keccak_f.sv` | 47 | Keccak-f[1600] top-level wrapper |
| **Total** | **3,502** | |

`falcon_decode.sv` and `falcon_normcheck.sv` (580 lines combined) are new
this session; `ntt_engine.sv` and `vrf_axi_top.sv` also grew (on-chip
buffer, two new job-front-end wirings) but no reliable prior-baseline line
count was recorded to state an exact delta.

**Register/control-plane surface**: 65 addressable 64-bit MMIO registers
(`vrf_ip/sw/vrf_axi.h`), of which 25 are the shared Keccak state array
(`DATA_0`..`DATA_24`) and 40 are distinct per-job control/address/parameter
registers across all 6 job front-ends. Two register-map reuse decisions
were made specifically to avoid adding new registers: `NTT_GM_ADDR` is
Falcon/ML-DSA's twiddle-table address for NTT/iNTT jobs and (in the now-
reverted VECMUL/VECSUB attempt) would have doubled as the second operand's
address — the general pattern of reusing one address register across a
job's mutually-exclusive modes is available for a future job that needs it.