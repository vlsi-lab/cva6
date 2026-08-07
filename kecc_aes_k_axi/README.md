# Keccak + AES Loosely-Coupled AXI Accelerator (kecc_aes_k_axi)

An AXI-memory-mapped peripheral wrapping `keccak_aes_k_top` -- the unified AES/Keccak
core from the [`kecc-aes-k`](../../kecc-aes-k) project -- into CVA6. Sibling to
`kecc_aes_k_xif/` (the tightly-coupled, CV-X-IF custom-instruction version of the same
underlying algorithms): where `kecc_aes_k_xif` offloads individual instructions,
`kecc_aes_k_axi` is a normal MMIO peripheral software drives through polled registers,
with no changes to the CPU pipeline or ISA decode.

## Directory tree

```
kecc_aes_k_axi/
├── hw/
│   ├── kecc_aes_k_axi_top.sv     AXI wrapper (axi_to_reg + reggen regfile + keccak_aes_k_top)
│   ├── regs/
│   │   ├── kecc_aes_k_axi.hjson  reggen register-map spec (see its own header comment)
│   │   ├── Makefile               `make reg` regenerates gen/*.sv + sw/kecc_aes_k_axi_regs.h
│   │   └── gen/                   reggen output (kecc_aes_k_axi_reg_{pkg,top}.sv)
│   └── rtl/
│       ├── v2/, v3/, v4/, v5/     vendored kecc-aes-k RTL, byte-for-byte per branch (v1 excluded)
│       ├── v2.flist, v3.flist,    per-version Verilator/Vivado file lists -- exactly one is
│       │   v4.flist, v5.flist     ever -F'd into a build, since all four versions define a
│       │                          module literally named `keccak_aes_k_top`
└── sw/
    ├── kecc_aes_k_axi_regs.h      reggen --cdefines output (register offsets/bit positions)
    └── kecc_aes_k_axi.{c,h}       bare-metal MMIO driver -- ONE driver for all 8 variants
                                    below, since the register map and handshake are identical
                                    across v2/v3/v4/v5 (only elaboration parameters differ)
```

## Versions

`keccak_aes_k_top`'s port list and handshake are bit-for-bit identical across v2/v3/v4/v5
(v1 is excluded -- superseded, not wired up here). Only the RTL file set and two
elaboration-time parameters differ:

| Version | Parameters | What's different |
|---|---|---|
| v2 | none | Milestone-2 baseline: one shared FSM/state register for AES+Keccak |
| v3 | none | On-the-fly AES key expansion (interleaved into block processing) |
| v4 | `SBOX_IMPL` (0/1/2 = serial_rom/dp_rom/bp) | Configurable AES S-box backend |
| v5 | `SBOX_IMPL`, `PARALLEL_SLICES` | Slice-serial Keccak datapath (smaller, more cycles) |

This means "the three versions of v4" and "the three versions of v5" are not six separate
RTL trees -- they're the same v4/v5 `rtl/` directory built three times with a different
`SBOX_IMPL` value. `kecc_aes_k_axi_top.sv` picks the right `keccak_aes_k_top` instantiation
form (with or without `SBOX_IMPL`/`PARALLEL_SLICES`) via
`` `ifdef KECC_AES_K_LOOSE_v4``/`` `elsif KECC_AES_K_LOOSE_v5``, set by
`core/Flist.cva6`'s `+define+KECC_AES_K_LOOSE_${AES_LOOSE_VERSION}`.

## The flag: `AES_VARIANT`

One environment variable selects the whole build, for both simulation and (eventually)
synthesis -- see `scripts/select_aes_variant.sh`:

```
AES_VARIANT = sw | ise |
              loose_v2 | loose_v3 |
              loose_v4_serial_rom | loose_v4_dp_rom | loose_v4_bp |
              loose_v5_serial_rom | loose_v5_dp_rom | loose_v5_bp
```

For the `loose_*` values, sourcing `scripts/select_aes_variant.sh` exports two things a
`tests/loosely/<name>/run.sh` needs before calling `cva6.py`:
- `TARGET_CFG` -- which `core/include/cv64a6_imac_crypto_loose_*_config_pkg.sv` gets
  compiled (sets `CVA6Cfg.LooseAesEn`/`LooseAesVersion`/`LooseAesSboxImpl`/
  `LooseAesParallelSlices`). `DV_TARGET` stays `cv64a6_imac_crypto` regardless (`cva6.py`'s
  own `--target` whitelist doesn't know the `loose_*` names, only `--mabi`/`--isa`, which
  are identical across every `loose_*` config).
- `AES_LOOSE_VERSION` -- `v2`/`v3`/`v4`/`v5`, which directory's `.flist`
  `core/Flist.cva6`'s `-F` picks up.

`corev_apu/fpga/src/ariane_xilinx.sv` and `corev_apu/tb/ariane_testharness.sv` both gate
the peripheral's actual instantiation on `CVA6Cfg.LooseAesEn` (an AXI decode-error slave
otherwise), mirroring `ariane.sv`'s existing `gen_cvxif`/`gen_COPRO_NONE` pattern for the
ISE coprocessor.

## Verified results

All 8 variants pass their `keccak_core`/`aes_core` KAT tests in real Verilator RTL
simulation of the full CVA6 SoC -- see `tests/README.md`'s "Results — loosely-coupled"
section for the cycle-count table.

## Adding v3/v4/v5-sub-variants beyond what's here, or a future v6

1. Vendor `kecc-aes-k` branch `rtl/` into `kecc_aes_k_axi/hw/rtl/vN/` (see any existing
   `vN/` for the exact file set; use `git ls-tree -r --name-only <branch> -- rtl` to get
   the authoritative list, excluding `rtl/keccak_ip/`).
2. Write `kecc_aes_k_axi/hw/rtl/vN.flist` (copy the closest existing one; if the version
   adds `SBOX_IMPL`/other elaboration parameters or `$readmemh`-loaded files, see v4/v5's
   `.flist` for the `AES_SBOX_MEM_PATH` override pattern and its two documented gotchas:
   `+define+` values need `\"..\"` escaped quotes, not plain `"..` -- Verilator's `-f`
   parser strips unescaped ones -- and `${VAR}` tokens are NOT expanded inside a
   `+define+NAME=value` token at all, only as standalone file-path tokens on their own
   line, so use a plain path relative to `verif/sim/` (where the simulation binary
   actually runs), not `${CVA6_REPO_DIR}`).
3. If the version's parameter list differs from anything already handled, add a matching
   `` `ifdef KECC_AES_K_LOOSE_vN`` branch to `kecc_aes_k_axi_top.sv`'s instantiation.
4. Add one `cv64a6_imac_crypto_loose_vN[_variant]_config_pkg.sv` per meaningful
   parameter combination (copy the closest existing one, change `LooseAesVersion`/
   `LooseAesSboxImpl`/`LooseAesParallelSlices`).
5. Add the matching case(s) to `scripts/select_aes_variant.sh`.
6. No register map, driver, AXI wrapper shape, or address-map change needed -- confirmed
   invariant across every version so far.
7. Verify: `AES_VARIANT=loose_vN[_variant] bash tests/loosely/keccak_core/run.sh` and
   `.../aes_core/run.sh`, checking the resulting `verif/sim/out_*/veri-testharness_sim/
   {keccak_core,aes_core}.cv64a6_imac_crypto.log.iss` for `terminated with no errors`
   (not `cva6.py`'s own exit code -- see `tests/README.md`'s note on this).
