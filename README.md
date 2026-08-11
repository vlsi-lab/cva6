# CVA6 + AES/Keccak Hardware Acceleration

A fork of the [CVA6](https://github.com/openhwgroup/cva6) RISC-V core exploring
three different ways to accelerate a unified AES/Keccak crypto primitive
(the [`kecc-aes-k`](https://github.com/vlsi-lab/kecc-aes-k) core), plus an
area-optimized redesign of the third:

| Approach | How it works | Directory |
|---|---|---|
| **Software** | No hardware acceleration, pure C reference implementation | `tests/software/` |
| **Tightly-coupled** | Custom RISC-V instructions via the CV-X-IF coprocessor interface, decoded inline in the CPU pipeline | `kecc_aes_k_xif/` |
| **Loosely-coupled** | An AXI-memory-mapped peripheral, driven by polled MMIO registers, no pipeline/decoder changes | `kecc_aes_k_axi/` |

**Full results (performance + FPGA area, all implementations and variants):
[`result.md`](result.md).**

## The `AES_VARIANT` flag

One environment variable selects which implementation gets built, for both
simulation (`veri-testharness`) and Vivado synthesis -- see
[`scripts/select_aes_variant.sh`](scripts/select_aes_variant.sh):

```
AES_VARIANT = sw | ise |
              loose_v2 | loose_v2_unified | loose_v3 |
              loose_v4_serial_rom | loose_v4_dp_rom | loose_v4_bp |
              loose_v5_serial_rom | loose_v5_dp_rom | loose_v5_bp
```

```bash
AES_VARIANT=loose_v2 bash tests/loosely/aes_cbc/run.sh    # one test
bash tests/run_all.sh loose_v2 all 1                      # the whole 22-test suite
```

### What differs between the loosely-coupled variants

`keccak_aes_k_top`'s port list and handshake are bit-for-bit identical across
v2/v3/v4/v5 -- "the three versions of v4" and "the three versions of v5" are
the same RTL built three times with a different `SBOX_IMPL` value, not six
separate RTL trees. `v2_unified` is a different wrapper/core pairing built on
top of v2's datapath, not another v2/v3/v4/v5 point.

| Variant | Parameters | What's different | Measured vs. v2 |
|---|---|---|---|
| `v2` | none | Baseline: one shared FSM/register for AES+Keccak, separate AXI register file | reference |
| `v2_unified` | none | **No internal working-state register at all** -- the AXI register file itself is the core's only storage, for both Keccak and AES (see below) | cycle-identical on 21/22 tests; **-14% LUTs / -26% FFs** |
| `v3` | none | On-the-fly AES key expansion (interleaved into block processing) | Keccak-side identical; small AES-side overhead |
| `v4` | `SBOX_IMPL` (0/1/2 = serial_rom/dp_rom/bp) | Configurable AES S-box backend | `SBOX_IMPL` has **zero** effect on cycle count or area for v4 |
| `v5` | `SBOX_IMPL`, `PARALLEL_SLICES` | Slice-serial Keccak datapath (smaller, more cycles) | ~40% smaller area, measurably slower everywhere (including Keccak-only ops); `bp` `SBOX_IMPL` recovers v3's AES speed on 6/12 AES tests |

Full per-test cycle counts, instruction counts, and synthesized LUT/FF/Slice
numbers for every one of these: **[`result.md`](result.md)**.

## The unified-storage redesign (`v2_unified`)

Modeled on the sibling [`cva6-keccak-loosely`](../cva6-keccak-loosely) project's
Keccak-only `keccak_dp.sv` pattern (state read live from the register file every
cycle, written back into the same registers every round -- no separate internal
copy), extended here to AES: `BLOCK0`/`BLOCK1` are hardware-writable and serve
as both the input staging register *and* the round-by-round working register
*and* the result (no separate `RESULT0`/`RESULT1` at all). AES's expanded key
schedule stays private/internal either way -- it was never AXI-visible to
begin with.

New RTL: `kecc_aes_k_axi/hw/rtl/v2_unified/keccak_aes_k_top_unified.sv`
(core), `kecc_aes_k_axi/hw/kecc_aes_k_axi_unified_top.sv` (wrapper),
`kecc_aes_k_axi/hw/regs/kecc_aes_k_axi_unified.hjson` (register map). All
22/22 tests pass; see [`result.md`](result.md#results--unified-storage-redesign-loose_v2_unified)
for the full performance/area comparison and what porting this to v3/v4/v5
would take (not done yet -- v2 only, so far).

## Directory map

- [`tests/`](tests/) -- the three (soon four) test trees and
  [`result.md`](result.md), the actual results.
- [`kecc_aes_k_xif/`](kecc_aes_k_xif/) -- tightly-coupled CV-X-IF coprocessor RTL.
- [`kecc_aes_k_axi/`](kecc_aes_k_axi/) -- loosely-coupled AXI accelerator RTL
  (both the non-unified and unified designs), plus
  [`kecc_aes_k_axi/synth_area/`](kecc_aes_k_axi/synth_area/) (Vivado
  out-of-context area synthesis) and [its own README](kecc_aes_k_axi/README.md)
  for the register map / build-flag mechanics in more detail.
- [`corev_apu/fpga/synth_area/`](corev_apu/fpga/synth_area/) -- Vivado
  out-of-context area synthesis for the whole CVA6 + tightly-coupled system.
- `scripts/select_aes_variant.sh` -- the `AES_VARIANT` dispatcher described above.

## Branch history

- `master` -- unmodified upstream CVA6 fork point.
- `keccak_tightly` -- adds the tightly-coupled `kecc_aes_k_xif` coprocessor
  and the software/tightly benchmark suite.
- `kecc-aes-k` -- adds the loosely-coupled `kecc_aes_k_axi` peripheral (all 8
  RTL variants) and the `tests/loosely/` suite, on top of `keccak_tightly`.
- **`v6`** (this branch) -- the `v2_unified` area-optimized redesign, the
  full 8-variant performance + area comparison, and this README, on top of
  `kecc-aes-k`.

## Reproducing results

See [`result.md`](result.md#reproducing) for the exact commands
behind every number in this repo -- simulation, KAT verification, and Vivado
synthesis alike.
