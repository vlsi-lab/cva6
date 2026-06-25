# CVA6 HASH Coprocessor Tests

This directory contains simulation tests for the custom HASH coprocessor on CVA6 (custom opcode `0x5B`).
All tests run inside the CVA6 Verilator simulation (`veri-testharness`) and compare a software reference against the hardware accelerator, printing cycle counts and a speedup ratio.

---

## Quick start

All tests must be launched **from the CVA6 repo root** (the directory that contains `verif/`).

```bash
# Interactive menu — picks one unit test and runs it
bash tests/run_tests.sh

# Interactive menu — picks one SPHINCS+ full-flow variant
bash tests/run_spx.sh

# Batch — run all SPHINCS+ variants for keygen + sign + verify
bash tests/run_spx_batch.sh --mode baseline all
bash tests/run_spx_batch.sh --mode optimized all
bash tests/run_spx_batch.sh --mode all all      # 36 simulations total
```

---

## Top-level scripts

| Script | What it does |
|---|---|
| `run_tests.sh` | Interactive numbered menu of all unit tests. Pick a number → runs that test's `run.sh`. |
| `run_spx.sh` | Interactive menu of SPHINCS+ variants (baseline and optimized). Pick one → runs it. |
| `run_spx_batch.sh` | Non-interactive batch driver for SPHINCS+. Accepts `--mode`, `--variants`, phases (`keygen sign verify all`). Saves `.log.iss` files and a `summary.tsv` under `results/spx_batch_<timestamp>/`. |
| `run_tests_cw305.sh` | Same as `run_tests.sh` but uses **CW305 build flags** (`rv64imac`, `-Os`) for SPHINCS+ tests (for FPGA side-channel measurements). Non-SPHINCS tests fall back to their default flags. |
| `run_spx_cw305.sh` | Same as `run_spx.sh` but with CW305 build flags. Thin wrapper around `run_spx_batch_cw305.sh`. |
| `run_spx_batch_cw305.sh` | Same as `run_spx_batch.sh` but with CW305 build flags. |

### Simulation vs CW305 flags

| Flag | Standard (`run_tests.sh` / `run_spx.sh`) | CW305 (`*_cw305.sh`) |
|---|---|---|
| Architecture | `rv64imafdc` (with FP) | `rv64imac` (no FP) |
| Optimization | `-O2` | `-Os` (size optimized) |
| Runtime | `crt.S` / `test.ld` | `cw305_crt.S` / `cw305_linker.ld` |
| Purpose | RTL simulation | Side-channel on CW305 FPGA |

---

## Unit tests (accessible via `run_tests.sh`)

Each of these lives in its own subdirectory and has a `run.sh` that can also be called directly.

### `hello-world`

**What it does:** Basic sanity check. Prints a hello message over simulated UART and exits.
**Use it to:** Verify the simulation environment is set up correctly before running heavier tests.

```bash
bash tests/hello-world/run.sh
```

---

### `keccak-permute`

**What it does:** Runs **one Keccak-f[1600] permutation** in both software and hardware on the same deterministic input, then compares all 25 output lanes. Uses the dual-lane `HASH_LOAD2` instruction to halve load cycles (13 vs 25 cycles).

**Pass condition:** All 25 lanes match. Prints `RESULT: PASS` and a SW/HW speedup ratio.

```bash
bash tests/keccak-permute/run.sh
```

---

### `keccak-abs`

**What it does:** Full Keccak absorption suite — runs SW (FIPS-202) and HW accelerated versions of:
- SHA3-256 single block (`"abc"`)
- SHA3-512 single block (`"abc"`)
- SHA3-256 multi-block (200-byte input)
- SHAKE128 XOF (consistency check)
- SHAKE256 XOF (consistency check)
- SHAKE128 multi-squeeze (500-byte output)

**Pass condition:** All outputs match expected values and each other.

```bash
bash tests/keccak-abs/run.sh
```

---

### `keccak-abs-sha3-256-single-block`

**What it does:** Focused SHA3-256 test on the single-block input `"abc"`. Runs SW FIPS-202 and HW `sha3_256_hw()`, checks against the known answer `3a985da7...`.

```bash
bash tests/keccak-abs-sha3-256-single-block/run.sh
```

---

### `keccak-abs-sha3-256-multi-block`

**What it does:** SHA3-256 on a 200-byte input (which spans multiple Keccak rate-blocks). Compares SW vs HW output.

```bash
bash tests/keccak-abs-sha3-256-multi-block/run.sh
```

---

### `keccak-abs-shake256`

**What it does:** SHAKE256 on a 100-byte input, 64-byte output. Runs SW and HW and compares.

```bash
bash tests/keccak-abs-shake256/run.sh
```

---

### `keccak-abs-multi-squeeze`

**What it does:** SHAKE128 with a large **500-byte output**, requiring multiple squeeze permutations. Compares SW vs HW byte-for-byte and measures the speedup.

```bash
bash tests/keccak-abs-multi-squeeze/run.sh
```

---

### `thash`

**What it does:** Tests the SPHINCS+ **`thash1`** (1-input tweakable hash) via the HASH coprocessor, across all 6 SPHINCS+ parameter sets: `128f-robust`, `128f-simple`, `192f-robust`, `192f-simple`, `256f-robust`, `256f-simple`. Runs 2 test cases per variant, comparing SW (`spx_ref_thash`) vs HW (`spx_hw_exec`).

```bash
bash tests/thash/run.sh
```

---

### `thash2`

**What it does:** Same as `thash` but for **`thash2`** (2-input tweakable hash, used in Merkle tree compression). Doubles the input width (2×n bytes).

```bash
bash tests/thash2/run.sh
```

---

### `thash-wots`

**What it does:** Two sub-tests per SPHINCS+ variant:
1. A single `thash1` call (same as `thash`).
2. A **WOTS+ chain** of 15 sequential `thash1` calls (simulating a WOTS+ hash chain step).

Useful for measuring the cumulative speedup of iterated HW hashing.

```bash
bash tests/thash-wots/run.sh
```

---

### `prf-addr`

**What it does:** Tests **`PRF_addr`** — the SPHINCS+ pseudorandom function that derives secret key material from `(SK.seed, PK.seed, ADRS)`. Runs SW reference vs HW for all 6 parameter sets.

```bash
bash tests/prf-addr/run.sh
```

---

### `chain-lengths`

**What it does:** Tests the **WOTS+ `chain_lengths`** algorithm, which converts a WOTS+ message hash into a vector of nibbles (chain step counts). Includes 3 parameter-set variants (128f/192f/256f), each with pre-computed test vectors. Compares SW (`chain_lengths_sw`) vs HW (`chain_lengths_hw_128f/192f/256f`).

```bash
bash tests/chain-lengths/run.sh
```

---

### `trigger`

**What it does:** Tests the **AXI-mapped trigger IP** peripheral at `0x41000000`. Reads the STATUS register, pulses the trigger output 3 times (START/STOP), and reads back GPIO_O.

**Purpose:** Used for side-channel power measurements — the trigger signal tells the oscilloscope when a cryptographic operation starts/stops. This test verifies the peripheral responds correctly in simulation before using it on the CW305 FPGA.

```bash
bash tests/trigger/run.sh
```

---

## SPHINCS+ / SLH-DSA full-flow tests (`pqc/`)

These are complete SLH-DSA (NIST PQC standard, formerly SPHINCS+) key generation, signing, and verification flows. They live under `pqc/` and are driven by `run_spx.sh` / `run_spx_batch.sh`.

### Directory layout

```
pqc/
├── baseline/DS/SLH-DSA/
│   ├── SPHINCS-128f-robust/    # n=16, SHAKE-based, robust tweak
│   ├── SPHINCS-128f-simple/    # n=16, SHAKE-based, simple tweak
│   ├── SPHINCS-192f-robust/    # n=24
│   ├── SPHINCS-192f-simple/    # n=24
│   ├── SPHINCS-256f-robust/    # n=32
│   └── SPHINCS-256f-simple/    # n=32
└── optimized/DS/SLH-DSA/
    └── ... (same 6 variants)
```

### Baseline vs Optimized

| | Baseline | Optimized |
|---|---|---|
| Keccak implementation | Pure C (FIPS-202) | Uses the HASH coprocessor (`keccak_coproc.S`) |
| Extra source file | — | `keccak_coproc.S` compiled in |
| Purpose | Software reference | Measures HW speedup on a full PQC signature |

### Phases

Each variant can be tested in three phases, controlled by compile-time defines:

| Phase | Define | What runs |
|---|---|---|
| `keygen` | `-DTEST_KEY=1` | Key pair generation |
| `sign` | `-DTEST_SIGN=1` | Message signing |
| `verify` | `-DTEST_SIGN_OPEN=1` | Signature verification |

### Running a single SPHINCS+ variant interactively

```bash
# Standard simulation flags
bash tests/run_spx.sh

# CW305 FPGA flags
bash tests/run_spx_cw305.sh
```

### Running all variants in batch

```bash
# All 18 baseline simulations (6 variants × 3 phases)
bash tests/run_spx_batch.sh --mode baseline keygen sign verify

# All 6 optimized variants, keygen only
bash tests/run_spx_batch.sh --mode optimized keygen

# Everything (36 simulations)
bash tests/run_spx_batch.sh --mode all all

# Custom subset of variants
bash tests/run_spx_batch.sh --mode optimized --variants "SPHINCS-128f-robust SPHINCS-256f-simple" all

# Save results to a specific directory
bash tests/run_spx_batch.sh --mode baseline --results-dir /tmp/my_results keygen sign verify
```

Results are saved as `<mode>-<variant>-<phase>.log.iss` plus a `summary.tsv` with mode/variant/phase/status/duration columns.

---

## Shared infrastructure

| Path | Purpose |
|---|---|
| `inc/hash_ip.h` | Hardware coprocessor intrinsics: `hash_init()`, `hash_load()`, `hash_load2()`, `hash_kperm()`, `hash_store()` |
| `inc/hash_coproc.S` | Assembly wrapper for the HASH coprocessor |
| `inc/uart.h` / `inc/uart.c` | UART driver used in simulation |
| `inc/compat.h` | Portability helpers |
| `sphincs_ref_impl.h` | Inline SPHINCS+ reference implementation used by `thash`, `thash2`, `thash-wots`, `prf-addr` |
| `api.h` | Kyber-512 API declarations (legacy, not used by current tests) |
| `results/` | Output directory for batch simulation logs |

---

## Environment variables

| Variable | Default | Effect |
|---|---|---|
| `HASH_TEST_TIMEOUT` | `100000000000` | RTL watchdog timeout (simulation cycles) |
| `HASH_ISS_TIMEOUT` | `1000000` | `cva6.py` wall-clock timeout (seconds) |
| `DV_SIMULATORS` | `veri-testharness` | Which simulator to use |
| `DV_OPTS` | _(empty)_ | Extra options passed to `cva6.py` |
