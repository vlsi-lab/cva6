# FPGA area synthesis (`corev_apu/fpga/synth_area/`)

Out-of-context Vivado synthesis of the CVA6 core (`ariane`) with the
`kecc_aes_k_xif` coprocessor tightly-coupled via CV-X-IF -- area/timing
numbers only, no bitstream, no CW305 pin mapping (`ariane` is a CPU
subsystem, not a flashable top-level). This is what `tests/result.md`'s
"Results -- Area (Vivado synthesis)" section is generated from. Target
board: CW305 (Digilent/NewAE), Artix-7 100T, part `xc7a100tftg256-2`.

This is a sibling flow to `kecc-aes-k/fpga.md`'s own out-of-context
synthesis of the standalone (loosely-coupled) `keccak_aes_k_top` -- the two
are meant to be compared directly: same part, same OOC methodology, same
virtual 100 MHz clock, same Vivado version (2024.1).

## Why out-of-context, and why a separate flow from `corev_apu/fpga/`

`corev_apu/fpga/` is CVA6's real board-bring-up flow: it generates Xilinx
IP cores (clock wizard, AXI converters, quad-SPI, etc.), builds a bitstream
via `ariane_xilinx.sv`, and is meant to actually boot on a board. That flow
answers "does this run on hardware"; this one answers "how much area does
the coprocessor cost" -- a much cheaper question that doesn't need a
pinout, IP generation, or even a memory controller.

`synth_design -mode out_of_context` against a single virtual clock on
`clk_i` gives real LUT/FF/BRAM/DSP numbers on the real target part without
any of that, using `ariane_synth_top` (`corev_apu/fpga/synth_area/rtl/ariane_synth_top.sv`)
as a minimal wrapper that binds CVA6's `CVA6Cfg` parameter to the crypto
config and exposes only `ariane`'s own core-level ports (clock/reset, boot
address, hart id, IRQ/IPI/timer/debug, an AXI-like `noc_req_o`/`noc_resp_i`
memory port). No DDR, no UART, no Ethernet, no JTAG -- those live in
`ariane_xilinx.sv` and aren't part of either the CVA6 core or the
coprocessor's own area.

## Why this reports three numbers, not one

`ariane_synth_top` instantiates `ariane`, which in turn instantiates both
pieces being compared as distinct, separately-named sub-instances:

```
ariane_synth_top
  i_ariane                                                       (ariane)
    i_cva6                                                       (cva6)                <- CVA6 core alone
    gen_cvxif.gen_COPRO_KECC_AES_K.i_kecc_aes_k_xif_coprocessor  (kecc_aes_k_xif)       <- coprocessor alone
```

`report_utilization -hierarchical` (run once, post-`opt_design`) reports
every level of that hierarchy in one table, so `scripts/report_area.py`
pulls the three rows that matter -- whole system, CVA6 core alone, and
coprocessor alone -- out of that single report instead of requiring three
separate synthesis runs. The coprocessor-alone row is the number to set
against `keccak_aes_k_top`'s own standalone OOC numbers in
`kecc-aes-k/result.md` for the loosely-coupled comparison; the
CVA6-core-alone row is the fixed cost either integration style has to
carry regardless of coupling strategy.

## Config used

`ariane`'s own `CVA6Cfg` parameter defaults to `config_pkg::cva6_cfg_empty`
(`CvxifEn = 0` -- the coprocessor wouldn't even be instantiated). This flow
compiles `core/include/cv64a6_imac_crypto_config_pkg.sv` as the
`cva6_config_pkg` package instead -- the only config in this repo with
`CvxifEn == 1` and `CoproType == COPRO_KECC_AES_K` (see
`kecc_aes_k_xif/README.md`), and the same config this repo's own
`verif/sim/cva6.py`-driven tests (`tests/keccak64/run.sh`,
`tests/ml-kem-512/run.sh`) already use. Note that config also has
`RVF = RVD = 1` (hardware FPU enabled) despite its `imac` name (the ISA
string used for spike/tests is `rv64imac`, no F/D) -- this matters for the
results below, since the FPU dominates the CVA6 core's area.

## Layout

- `rtl/ariane_synth_top.sv` -- the synthesis-only top. Binds `CVA6Cfg` and
  instantiates `ariane` with its core-level ports exposed; no board logic.
- `scripts/run_synth.tcl` -- the synthesis script; see "Modifications
  needed to make this build" below for what it does beyond a plain
  `read_verilog` + `synth_design`.
- `run_synth.sh` -- driver script. Converts WSL paths to Windows paths
  (`wslpath -w`) and calls Vivado through `~/bin/vivado`, since Vivado on
  this machine is a native Windows install, not a WSL/Linux binary --
  identical setup to `kecc-aes-k/fpga.md`'s own wrapper, reused here as-is.
- `scripts/report_area.py` -- parses `reports/ariane_synth_top.utilization.rpt`
  and prints/writes `reports/area_summary.md`, the three-way (system / CVA6
  core / coprocessor) area summary reproduced below.
- `reports/` -- tracked in git: `ariane_synth_top.utilization.rpt`,
  `.timing_summary.rpt`, `.timing_WORST_20.rpt`, `area_summary.md`. This is
  the evidence behind the numbers below and in `tests/result.md`.
- `work/`, `logs/`, `.Xil/` -- Vivado's own build products (checkpoints,
  batch logs, journals, cache) -- regenerable, gitignored.

## Prerequisites

Same as `kecc-aes-k/fpga.md`: a Windows Vivado install reachable from this
WSL shell via `~/bin/vivado` (this machine: Vivado 2024.1 at
`C:\Xilinx\Vivado\2024.1\bin\vivado.bat`), plus `wslpath`. `git submodule
status` should show `core/cvfpu` (and the repo's other submodules)
checked out before running this -- `core/Flist.cva6` (see below) points
straight at it.

## Usage

```
cd corev_apu/fpga/synth_area
./run_synth.sh                                  # default: xc7a100tftg256-2, 10ns/100MHz
CLK_PERIOD_NS=8 ./run_synth.sh                   # override the clock target
XILINX_PART=xc7a35tcpg236-1 ./run_synth.sh       # override the part
python3 scripts/report_area.py                  # after a run: print/write the 3-way summary
```

## Modifications needed to make this build

None of these are changes to existing tracked files -- `run_synth.tcl`
works around all of them at the file-list/parameter level, entirely inside
the new `corev_apu/fpga/synth_area/` flow:

1. **File list**: `Flist.ariane` (repo root) looks like the obvious RTL
   file list to reuse for an `ariane`-level build, but as checked out here
   it references several files that no longer exist --
   `core/include/acc_pkg.sv`, `core/mmu_sv39/*.sv`,
   `core/include/cvxif_pkg.sv` -- stale relative to the current
   `core/cva6_mmu/` layout and macro-based `cvxif_types.svh`. Used
   `core/Flist.cva6` instead (the actively-maintained "CORE-ONLY
   manifest", parameterized by `${CVA6_REPO_DIR}`/`${TARGET_CFG}`, already
   used by this repo's own `verif/sim/cva6.py`-driven tests). It doesn't
   cover `corev_apu/src/ariane.sv` itself (core-only list) or the
   `ariane_axi::req_t`/`resp_t` types `ariane_synth_top`'s ports use, so
   `run_synth.tcl` appends `corev_apu/tb/ariane_axi_pkg.sv`,
   `corev_apu/src/ariane.sv`, and `rtl/ariane_synth_top.sv` on top of that
   base.
2. **Config package**: swapped `${TARGET_CFG}` to `cv64a6_imac_crypto` (see
   "Config used" above) -- `ariane`'s `CVA6Cfg` parameter binds to whichever
   `cva6_config_pkg` package ends up compiled into the run, and the default
   is `CvxifEn = 0`.
3. **hpdcache dropped**: `core/Flist.cva6` pulls in an external hpdcache
   submodule (its own nested `-F .../hpdcache.Flist`, env-var-rooted paths)
   that the crypto config never uses (`DCacheType == WT`) -- those
   HPDCACHE-only `cache_subsystem` modules sit behind an elaboration-time
   `generate if (CVA6Cfg.DCacheType == ...)` a WT config never takes, so
   Vivado never needs those files to exist. Dropped to avoid depending on
   files/paths this flow doesn't actually need.
4. **RVFI probe types**: `ariane`'s `rvfi_probes_instr_t`/`rvfi_probes_csr_t`
   parameters default to plain `logic` (a stand-in, not a real struct).
   `ariane_synth_top` initially left them at that default, since this
   synthesis-only top never reads `rvfi_probes_o` -- but `csr_regfile.sv`
   unconditionally does `rvfi_csr_o.fcsr_q = ...` (and ~30 more per-CSR
   field assignments) regardless of whether anything downstream consumes
   them, so with the `logic` default those field-selects don't exist and
   Vivado fails elaboration ("cannot resolve hierarchical name for the
   item 'fcsr_q'"). Fixed by computing the real types via the
   `` `RVFI_PROBES_INSTR_T``/`` `RVFI_PROBES_CSR_T`` macros in
   `rtl/ariane_synth_top.sv`, the same idiom every other CVA6 top
   (`ariane_xilinx.sv`, `ariane_testharness.sv`, ...) already uses --
   `rvfi_probes_o` is still left unconnected, it just now has to be typed
   correctly to compile.
5. **SRAM technology cell**: the WT dcache's tag/data SRAMs go through
   `common/local/util/tc_sram_wrapper.sv`, which wraps the
   technology-agnostic `vendor/pulp-platform/tech_cells_generic` `tc_sram`
   inside `// synthesis translate_off` -- a simulation-only behavioral
   model, deliberately excluded from synthesis upstream, which leaves
   `tc_sram_wrapper` an empty/undefined black box for Vivado (`opt_design`
   fails DRC `INBB-3`, "Black Box Instances"). Swapped it (and `tc_sram.sv`,
   its only consumer) for `common/local/util/tc_sram_fpga_wrapper.sv` --
   the module-for-module Xilinx replacement `Bender.yml`'s own
   `target: all(fpga, xilinx)` selects for exactly this situation -- backed
   by the inferable `vendor/pulp-platform/fpga-support/rtl/SyncSpRamBeNx64.sv`
   (defaults to `FPGA_TARGET_XILINX` when nothing else is defined).

## Results -- Area (Vivado synthesis)

Tool: Vivado v2024.1 (win64). Part: `xc7a100tftg256-2` (CW305, Artix-7
100T). Constraint: single virtual clock on `clk_i`, 10 ns period (100 MHz)
-- not tuned for timing closure (no `place_design`/`route_design` in this
flow; the timing report exists but its WNS is not representative, see
`reports/ariane_synth_top.timing_summary.rpt`). Config:
`cv64a6_imac_crypto` (RVF/RVD/hardware FPU enabled). Reproduce with
`./corev_apu/fpga/synth_area/run_synth.sh`; full reports under
`corev_apu/fpga/synth_area/reports/`. Measured 2026-08-04.

| Metric | Whole system (`ariane_synth_top`) | CVA6 core alone (`i_cva6`) | `kecc_aes_k_xif` coprocessor alone |
|---|---:|---:|---:|
| Total LUTs | 56001 | 55452 | **375** |
| FFs | 23889 | 23623 | **265** |
| RAMB36 | 36 | 36 | 0 |
| RAMB18 | 0 | 0 | 0 |
| DSP Blocks | 27 | 27 | 0 |

The coprocessor is **375/56001 = 0.67%** of system Total LUTs and
**265/23889 = 1.11%** of system FFs -- tiny relative to the CVA6 core,
which is dominated by the FPU (RVF/RVD enabled in this config; see "Config
used" above). It uses 0 BRAM and 0 DSP -- every `xor3`/`xandn`/`rxri`/
`aes64*` datapath is pure combinational/register logic (consistent with
`kecc_aes_k_xif_aes_sboxes.sv`'s riscv-crypto tower-field S-box, see
`implementation.md`: no ROM, no ROM-derived BRAM inference anywhere in the
coprocessor).

Compare against `kecc-aes-k/result.md`'s own "Area (Vivado synthesis)"
section (`keccak_aes_k_top` standalone, same part/methodology): that
number is the loosely-coupled IP's area on its own, without any CV-X-IF
integration logic or the CVA6 core it would sit beside on a real chip. The
gap between the two tells you what tight vs. loose coupling costs on the
IP's own area; the CVA6-core-alone row above (55452 LUT / 23623 FF) is the
fixed cost either integration style has to carry regardless.
