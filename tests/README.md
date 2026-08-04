# Software vs. tightly-coupled coprocessor benchmark suite

`tests/software/` and `tests/tightly/` run the **same 11 algorithms** two ways:

- **`tests/software/`** — pure software, no custom instructions.
- **`tests/tightly/`** — the same algorithms accelerated by the `kecc_aes_k_xif`
  tightly-coupled coprocessor (`xor3`/`xandn`/`rxri` for Keccak, `aes64es/esm/ds/dsm/ks2/im/ks1i`
  for AES64).

The directory names are deliberate: a future `tests/loosely/` tree (loosely-coupled
accelerator variant) is expected to reuse the same 11-test structure.

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
