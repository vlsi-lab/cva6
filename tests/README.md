# Software vs. tightly-coupled vs. loosely-coupled accelerator benchmark suite

`tests/software/`, `tests/tightly/`, and `tests/loosely/` run the same algorithms three
ways:

- **`tests/software/`** — pure software, no custom instructions.
- **`tests/tightly/`** — accelerated by the `kecc_aes_k_xif` tightly-coupled coprocessor
  (`xor3`/`xandn`/`rxri` for Keccak, `aes64es/esm/ds/dsm/ks2/im/ks1i` for AES64).
- **`tests/loosely/`** — accelerated by `kecc_aes_k_axi`, a loosely-coupled AXI-mapped
  peripheral wrapping the `keccak_aes_k_top` core from the `kecc-aes-k` project. Which
  RTL variant (v2/v3/v4/v5, and for v4/v5 which `SBOX_IMPL`) gets built is a single
  `AES_VARIANT` flag (see `scripts/select_aes_variant.sh`), not a separate branch per
  variant — `AES_VARIANT=loose_v2`, `loose_v3`, `loose_v4_serial_rom`, `loose_v4_dp_rom`,
  `loose_v4_bp`, `loose_v5_serial_rom`, `loose_v5_dp_rom`, `loose_v5_bp` are all built
  from this one tree. Only `keccak_core`/`aes_core` are ported here so far (the two
  primitives `keccak_aes_k_top` exposes directly); the other 9 `tightly`/`software` tests
  are composite algorithms built in software on top of a primitive and still need their
  driver swapped to `kecc_aes_k_axi`'s MMIO interface.

The directory names were deliberate from the start: `tests/loosely/` was reserving the
same 11-test structure `tests/software/`/`tests/tightly/` already use.

Both trees count clock cycles (`mcycle`) and retired instructions (`minstret`) around
just the benchmarked operation (`common/bench.h`), separately from program startup/UART
I/O overhead. 9 of the 11 tests share **byte-identical** `.c` source between the two
trees (they only call the shared `fips202.h` / `aes128_block.h` / `kmac.h` / `hmac.h` /
`aes_cbc.h` interfaces) — only the linked primitive implementation and `run.sh` build
flags differ. Expected values were computed independently via Python (`hashlib`/`hmac`
stdlib, `pycryptodome`'s `KMAC256`/`AES`), not hand-derived.

## Running

```bash
source tests/software/run.sh [name|all]   # interactive menu if no arg
source tests/tightly/run.sh  [name|all]
```

Each test also has its own standalone `tests/<tree>/<name>/run.sh`. Output artifacts land
in `verif/sim/out_<date>/veri-testharness_sim/<name>.cv64a6_imafdc_sv39.log*`, named after
the test (not the tree), since `cva6.py` derives the name from the source file's basename.

**Note:** `cva6.py` does not fail its own exit code on RTL/expected-value mismatches
(see the comment at `verif/sim/cva6.py:668`) — the real pass/fail signal is each test's
own printed `terminated with no errors` / `!!! mismatch !!!` line.

## Results (real RTL simulation, `veri-testharness`, target `cv64a6_imafdc_sv39`)

All 22 runs below passed with **zero mismatches**. Cycle/instruction counts are the
benchmarked region only (`cycles=`/`instrs=` as printed by each test), not the whole
program (which also includes UART output).

| Test | SW cycles | Tightly cycles | Speedup | SW instrs | Tightly instrs | Instr reduction |
|---|---:|---:|---:|---:|---:|---:|
| `keccak_core` | 5,253 | 3,181 | 1.65x | 4,837 | 2,366 | 2.04x |
| `aes_core` (key expansion) | 2,297 | 476 | 4.83x | 2,116 | 240 | 8.82x |
| `sha3_256` | 6,520 | 3,524 | 1.85x | 5,662 | 2,756 | 2.05x |
| `sha3_512` | 6,775 | 3,788 | 1.79x | 5,845 | 2,939 | 1.99x |
| `shake128_short` (32 B in) | 6,717 | 3,708 | 1.81x | 5,810 | 2,905 | 2.00x |
| `shake256_long` (2048 B in) | 99,770 | 54,750 | 1.82x | 92,869 | 46,374 | 2.00x |
| `kmac256` | 21,389 | 13,071 | 1.64x | 19,832 | 11,153 | 1.78x |
| `hmac_sha3_256` | 27,397 | 16,155 | 1.70x | 25,629 | 14,005 | 1.83x |
| `aes_encrypt` (ECB, 2 blocks) | 15,742 | 1,223 | 12.87x | 11,494 | 798 | 14.40x |
| `aes_decrypt` (ECB, 2 blocks) | 56,792 | 1,264 | 44.93x | 52,496 | 798 | 65.79x |
| `aes_cbc` (3 blocks, enc+dec) | 105,555 | 4,431 | 23.82x | 92,718 | 3,089 | 30.02x |

**Takeaways:**
- Keccak-based operations (SHA3/SHAKE/KMAC/HMAC) get a consistent **~1.6-1.9x** speedup
  from `xor3`/`xandn`/`rxri` -- the coprocessor accelerates the permutation's bitwise
  steps, but the surrounding sponge/padding logic stays in software either way.
- AES gets a much larger **5-45x** speedup, since `aes64*` replaces the software S-box
  lookup tables and GF(2^8) multiplication with single instructions. Decryption benefits
  the most, because software `InvMixColumns`' repeated `Multiply()` calls are far more
  expensive than the encryption path's simpler forward MixColumns.
- `aes_core` (key expansion alone) shows the coprocessor's largest *relative* win
  (4.8x cycles, 8.8x instructions) since it's almost entirely S-box/round-constant work
  with very little other overhead to dilute the comparison.

## Results — loosely-coupled (`tests/loosely/`, target `cv64a6_imac_crypto`)

All 16 runs below (8 RTL variants x 2 tests) passed with **zero mismatches**. Unlike
`tests/tightly/`'s `aes_core` (key expansion only), `tests/loosely/aes_core` benchmarks
one full AES-128 block encrypt against the FIPS-197 Appendix B vector, since
`keccak_aes_k_top`'s AXI register map only exposes the final block result, not the
intermediate round-key schedule — see `tests/loosely/aes_core/aes_core.c`'s header
comment.

| `AES_VARIANT` | `keccak_core` cycles | `keccak_core` instrs | `aes_core` cycles | `aes_core` instrs |
|---|---:|---:|---:|---:|
| `loose_v2` | 3,684 | 2,665 | 743 | 417 |
| `loose_v3` | 3,664 | 2,665 | 753 | 420 |
| `loose_v4_serial_rom` | 3,664 | 2,665 | 953 | 480 |
| `loose_v4_dp_rom` | 3,664 | 2,665 | 953 | 480 |
| `loose_v4_bp` | 3,664 | 2,665 | 953 | 480 |
| `loose_v5_serial_rom` | 4,069 | 2,785 | 953 | 480 |
| `loose_v5_dp_rom` | 4,069 | 2,785 | 953 | 480 |
| `loose_v5_bp` | 4,069 | 2,785 | 953 | 480 |

**Takeaways:**
- `keccak_core` cycles/instrs are identical across v3/v4 (all `SBOX_IMPL` choices) —
  expected, since none of those changes touch the Keccak datapath, only the AES S-box.
  v5's `keccak_core` cost is higher (4,069 vs. 3,664 cycles, +11%) because v5 replaces
  the full-width combinational Keccak round with a slice-serial datapath
  (`keccak_slice_serial.sv`, `PARALLEL_SLICES` bits/cycle) that trades cycles for area —
  the "smaller serial" tradeoff `kecc-aes-k`'s own `result.md` describes, and this is the
  first real confirmation it actually executes (not silently falling back to the
  full-width path) since it produces a *different, still-correct* cycle count.
- `aes_core` is identical within each version-family (v2/v3 have no `SBOX_IMPL` choice;
  v4/v5 share the same 953/480 regardless of which S-box backend is selected) — expected,
  since `SBOX_IMPL` changes the S-box's internal implementation/timing at the
  sub-instruction level in a way this coarse whole-operation cycle count doesn't resolve;
  differentiating the three backends needs a cycle-accurate per-round trace or an area
  comparison (see `kecc-aes-k/result.md`), not this benchmark.
- v3's AES path costs 10 more cycles than v2's despite v3's whole design point being
  "cheaper" key expansion (on-the-fly key schedule) — this benchmark does one AES
  operation (key schedule + one block) so it isn't structured to isolate that win; see
  `kecc-aes-k/result.md` for the dedicated comparison.

## Test list

| Name | What it exercises |
|---|---|
| `keccak_core` | One `KeccakF1600_StatePermute` call (known-answer vector). |
| `aes_core` | AES-128 key expansion alone (setup/schedule primitive). |
| `sha3_256` / `sha3_512` | Fixed-message hash. |
| `shake128_short` / `shake256_long` | XOF with short (32 B) vs. long (2048 B) input, to show cycle scaling with length. |
| `kmac256` | NIST SP 800-185 KMAC256 (cSHAKE-based MAC). |
| `hmac_sha3_256` | RFC 2104 HMAC using SHA3-256. |
| `aes_encrypt` / `aes_decrypt` | AES-128-ECB, 2 independent blocks (FIPS-197 vector + one extra block). |
| `aes_cbc` | AES-128-CBC, 3 chained blocks, encrypt then decrypt round-trip. |
