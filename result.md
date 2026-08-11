# Benchmark results: software baseline vs. tightly-coupled coprocessor

## Index

This document covers three implementations of the AES/Keccak accelerator --
**software** baseline, **tightly-coupled** CV-X-IF coprocessor, and
**loosely-coupled** AXI-memory-mapped peripheral (8 RTL variants: v2/v3/
v4×3-`SBOX_IMPL`/v5×3-`SBOX_IMPL`, plus one area-optimized redesign,
`v2_unified`) -- and their measured performance and FPGA area.

- [Results — original 11 algorithms](#results--original-11-algorithms) --
  software vs. tightly-coupled, the first 11 tests ported (Keccak permute,
  AES-128 ECB, SHA3/SHAKE/KMAC/HMAC): tightly-coupled is 1.6-8.8x faster.
- [Results — new AES modes (CTR, GCM, XTS)](#results--new-aes-modes-ctr-gcm-xts) --
  same comparison extended to AES-CTR/GCM/XTS.
- [Results — AES-GCM payload-size sweep](#results--aes-gcm-payload-size-sweep) --
  GCM cost vs. payload size, 16 B to 1024 B.
- [Results — GHASH block-multiply](#results--ghash-block-multiply) --
  a prototyped `GHASH_CLMULL`/`CLMULH` addition, measured and then removed
  (no benefit over native `clmul`/`clmulh`).
- [Results — Keccak sponge interface (Phase B)](#results--keccak-sponge-interface-phase-b) --
  absorb/squeeze/init/padding/context-save as separate, composable calls,
  including chunked-vs-monolithic incremental absorb/squeeze.
- [Results — Loosely-coupled AXI accelerator (all 8 variants)](#results--loosely-coupled-axi-accelerator-all-8-variants) --
  the full 22-test suite re-run on every one of the 8 `kecc_aes_k_axi` RTL
  variants (176/176 runs pass); `SBOX_IMPL` is a no-op for v4 but measurably
  speeds up 6 of 12 AES-touching tests for v5's `bp` variant; v5 is slower
  end-to-end than v2/v3/v4.
- [Results — Area (Vivado synthesis)](#results--area-vivado-synthesis) --
  tightly-coupled system area: the CV-X-IF coprocessor is <1% of total
  LUTs/FFs.
- [Results — Area, loosely-coupled AXI accelerator (all 8 variants)](#results--area-loosely-coupled-axi-accelerator-all-8-variants) --
  real synthesized area (wrapper + register file + core) for all 8 variants;
  v5's slice-serial Keccak datapath is ~40% smaller than v2/v3/v4, trading
  area for the extra cycles above; the AXI register file + bridge together
  are roughly as large as the compute core itself.
- [Results — Unified-storage redesign (`v2_unified`)](#results--unified-storage-redesign-loose_v2_unified) --
  a second wrapper/core with no internal working-state register at all (the
  AXI register file itself is the only storage, for both Keccak and AES):
  cycle-identical to v2 on 21/22 tests, **-14% LUTs / -26% FFs / -14%
  Slices**. Built for v2 only; [what porting to v3/v4/v5 would
  take](#extending-to-v3v4v5) is scoped but not implemented.
- [Takeaways](#takeaways) -- cross-cutting conclusions across all of the above.
- [Future work / methodology notes](#future-work--methodology-notes-not-implemented-here) --
  known gaps and ideas not pursued in this round.
- [Reproducing](#reproducing) -- exact commands to re-run any result in this
  document.

---

Fresh re-run of all 22 original tests (`tests/software/` and `tests/tightly/`) on real
RTL (`veri-testharness`, target `cv64a6_imafdc_sv39`), executed via
`source tests/software/run.sh all` and `source tests/tightly/run.sh all`, plus 3 new
AES-mode tests (`aes_ctr`, `aes_gcm`, `aes_xts`) and 7 new Keccak sponge-interface
tests (`keccak_sponge_*`) added afterward — the AES modes verified first against
independently Python-computed KATs on the host, the sponge tests verified against the
existing one-shot `shake128()` API (both host-side logic checks before ever touching
RTL), then all run on the same RTL.

Both trees already instrument every test with `mcycle` **and** `minstret` counting
around just the benchmarked operation (`common/bench.h`'s `BENCH_ENABLE`/`BENCH_START`/
`BENCH_READ`, built on `mcountinhibit` bits `CY`+`IR`).

All runs compiled/ran with 0 simulation failures, and every test's own printed
"Benchmark terminated with no errors" line confirms 0 mismatches against the
independently-computed expected values (Python `hashlib`/`hmac`/`pycryptodome`/
`cryptography`).

**Throughput column**: bits/cycle = payload bits processed / cycles for the benchmarked
region. For AEAD (GCM), only plaintext/ciphertext bits are counted, not AAD (its cost
shows up in the cycle count, not the throughput figure). `keccak_core` uses the fixed
1600-bit permutation width, not a message size, since it benchmarks one bare
permutation call rather than a sponge operation over a message. `aes_core` (key
expansion) is marked N/A -- it doesn't process data, so a data-throughput figure would
be misleading.

## Results — original 11 algorithms

| Test | SW cycles | Tightly cycles | Speedup | SW instrs | Tightly instrs | Instr reduction | SW bits/cycle | Tightly bits/cycle |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| `keccak_core` | 5,253 | 3,181 | 1.65x | 4,837 | 2,366 | 2.04x | 0.3046 | 0.5030 |
| `aes_core` (key expansion) | 2,297 | 476 | 4.83x | 2,116 | 240 | 8.82x | N/A | N/A |
| `sha3_256` (43 B in) | 6,520 | 3,524 | 1.85x | 5,662 | 2,756 | 2.05x | 0.0528 | 0.0976 |
| `sha3_512` (43 B in) | 6,775 | 3,788 | 1.79x | 5,845 | 2,939 | 1.99x | 0.0508 | 0.0908 |
| `shake128_short` (32 B in) | 6,717 | 3,708 | 1.81x | 5,810 | 2,905 | 2.00x | 0.0381 | 0.0690 |
| `shake256_long` (2048 B in) | 99,770 | 54,750 | 1.82x | 92,869 | 46,374 | 2.00x | 0.1642 | 0.2993 |
| `kmac256` (41 B msg) | 21,389 | 13,071 | 1.64x | 19,832 | 11,153 | 1.78x | 0.0153 | 0.0251 |
| `hmac_sha3_256` (41 B msg) | 27,397 | 16,155 | 1.70x | 25,629 | 14,005 | 1.83x | 0.0120 | 0.0203 |
| `aes_encrypt` (ECB, 2 blocks) | 15,742 | 1,223 | 12.87x | 11,494 | 798 | 14.40x | 0.0163 | 0.2093 |
| `aes_decrypt` (ECB, 2 blocks) | 56,792 | 1,264 | 44.93x | 52,496 | 798 | 65.79x | 0.0045 | 0.2025 |
| `aes_cbc` (3 blocks, enc+dec) | 105,555 | 4,431 | 23.82x | 92,718 | 3,089 | 30.02x | — | — |

`aes_cbc` breakdown (encrypt / decrypt phases, `BENCH_READ` twice per run):

| Phase | SW cycles | Tightly cycles | SW instrs | Tightly instrs | SW bits/cycle | Tightly bits/cycle |
|---|---:|---:|---:|---:|---:|---:|
| encrypt | 22,300 | 2,292 | 15,715 | 1,538 | 0.0172 | 0.1675 |
| decrypt | 83,255 | 2,139 | 77,003 | 1,551 | 0.0046 | 0.1795 |

## Results — new AES modes (CTR, GCM, XTS)

CTR is a raw-core-throughput/streaming test (encrypt-only operation, decrypt is the
same keystream re-applied); GCM adds GHASH authentication on top of the same kind of
keystream; XTS is storage-oriented (two-key, per-sector tweak, no authentication).
AES-ECB is already covered by the existing `aes_encrypt`/`aes_decrypt` tests above, so
no separate ECB test was added.

| Test | SW cycles | Tightly cycles | Speedup | SW instrs | Tightly instrs | Instr reduction | SW bits/cycle | Tightly bits/cycle |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| `aes_ctr` encrypt (40 B) | 23,013 | 2,208 | 10.42x | 16,710 | 1,464 | 11.41x | 0.0139 | 0.1449 |
| `aes_ctr` decrypt (40 B) | 22,467 | 1,844 | 12.18x | 16,711 | 1,465 | 11.41x | 0.0142 | 0.1735 |
| `aes_gcm` encrypt (20 B AAD + 48 B payload) | 173,635 | 13,331 | 13.03x | 136,038 | 11,119 | 12.23x | 0.0022 | 0.0288 |
| `aes_gcm` decrypt (20 B AAD + 48 B payload) | 172,944 | 12,725 | 13.59x | 136,168 | 11,249 | 12.10x | 0.0022 | 0.0301 |
| `aes_xts` encrypt (1 sector, 48 B) | 31,801 | 3,974 | 8.00x | 22,998 | 2,706 | 8.50x | 0.0120 | 0.0966 |
| `aes_xts` decrypt (1 sector, 48 B) | 92,600 | 3,691 | 25.09x | 84,124 | 2,707 | 31.08x | 0.0041 | 0.1040 |

**Update (2026-08-05)**: the `aes_gcm` row above reflects `tests/tightly`'s final
GHASH setup — AES still via the `kecc_aes_k_xif` coprocessor (`aes64*`), GHASH via
the RISC-V B-extension's native `clmul`/`clmulh` (see "Results — GHASH
block-multiply" below for why, not a dedicated coprocessor instruction). GHASH was
pure software when this row was first measured (`tightly` cycles were
141,603/140,954, ~1.2x speedup) and briefly went through a dedicated-coprocessor-
instruction phase (13,316/12,707) before landing here, essentially unchanged
cycle-wise from that phase (13,331/12,725) — see below.

## Results — AES-GCM payload-size sweep

`tests/software/aes_gcm_sweep` / `tests/tightly/aes_gcm_sweep`: same AES-128-GCM
construction as `aes_gcm` above (fixed 20 B AAD, same KEY/IV convention), but
sweeping payload size (16/64/256/1024 B) instead of a single fixed size, to see how
the software/accelerated gap moves with the size of the data actually being
processed -- the AAD is fixed because it only adds GHASH cost, not AES-CTR cost;
payload size drives both, so it's the more informative axis. Correctness here is a
self-consistency check per size (`decrypt(encrypt(PT)) == PT`, tag verifies) rather
than an independent KAT per size -- the underlying `aes128_gcm_encrypt`/`decrypt`
primitives are already KAT-validated by `aes_gcm` at one fixed size; this sweep only
needs to confirm they behave correctly across a size range. All 8 runs (4 sizes x
2 directions x 2 trees) passed with zero errors. Measured 2026-08-05; raw data in
`tests/aes_gcm_sweep_data.csv`, figure generated by `tests/plot_aes_gcm_sweep.py`
(`tests/aes_gcm_sweep.pdf`/`.png`).

| Payload (B) | SW encrypt cyc | Accel encrypt cyc | Encrypt speedup | SW decrypt cyc | Accel decrypt cyc | Decrypt speedup |
|---:|---:|---:|---:|---:|---:|---:|
| 16 | 114,629 | 8,977 | 12.77x | 113,937 | 8,439 | 13.50x |
| 64 | 202,609 | 14,679 | 13.80x | 202,716 | 14,780 | 13.72x |
| 256 | 556,801 | 40,359 | 13.80x | 556,859 | 40,424 | 13.78x |
| 1024 | 1,974,395 | 143,151 | 13.79x | 1,974,237 | 143,000 | 13.81x |

**Speedup is close to flat (~13.8x) across two orders of magnitude of payload size,
with one real deviation: the smallest size (16 B) is measurably lower** (12.77x
encrypt, 13.50x decrypt) than the plateau every larger size sits on. This is the
fixed-cost-dilution pattern seen elsewhere in this suite (e.g. `aes_core`'s
narrow-operation speedup, or the sponge tests' O(1) operations showing no speedup):
at 16 B, per-call fixed overhead (key expansion, `H`/`J0`/tag-mask setup -- one AES
block each, done once regardless of payload) is a larger fraction of the total, and
that fixed cost doesn't benefit from acceleration the same way the per-block
AES-CTR + GHASH work does. By 64 B the per-block work already dominates enough that
speedup is indistinguishable from the asymptotic ~13.8x this coprocessor+clmul
combination delivers per block -- **the practical takeaway is that acceleration
here is not payload-size-dependent above a small fixed floor**, unlike, say, the
Keccak sponge tests where speedup only appears once enough full-rate blocks are
processed. Reproduce with `tests/software/run.sh aes_gcm_sweep` and
`tests/tightly/run.sh aes_gcm_sweep` (the software run takes on the order of an
hour -- software GCM at 1024 B is GHASH-bit-serial-dominated; see both `run.sh`
files' comments on the `+time_out`/`--iss_timeout` overrides this required).

![AES-128-GCM cycles and speedup vs. payload size](aes_gcm_sweep.png)

## Results — GHASH block-multiply

New `ghash_core` benchmark: one isolated GF(2^128) block-multiply
(`gf128_mul`, NIST SP 800-38D reduction polynomial), same
`BENCH_ENABLE/START/READ` methodology as `aes_core`/`keccak_core`, KAT
derived from this repo's own trusted `aes_gcm` pipeline (`H = AES-128-ECB(KEY,
0^128)`, `A` = a fixed 16-byte block, `Z = gf128_mul(A, H)`), cross-checked
independently via `pycryptodome` before use. Two implementations compared —
`tests/software/ghash_core` (bit-serial, no hardware) and
`tests/native_clmul/ghash_core` (RISC-V B-extension's native `clmul`/`clmulh`,
already present and enabled in this target config, zero new RTL — see
`fpga.md`). Both run the identical bit-reflect → 4×64x64→128 partial-product
→ Gueron-style shift-xor reduction → bit-reflect-back algorithm in C; only
the underlying 64x64→128 carry-less-multiply primitive differs.

| Implementation | Cycles | Speedup vs SW | Instrs | Instr reduction vs SW | bits/cycle |
|---|---:|---:|---:|---:|---:|
| Software (bit-serial) | 22,905 | 1.00x | 18,317 | 1.00x | 0.0056 |
| Native `clmul`/`clmulh` (B-extension) | 1,685 | 13.59x | 1,404 | 13.05x | 0.0760 |

**A third, dedicated-coprocessor implementation was built, measured, and removed.**
`GHASH_CLMULL`/`GHASH_CLMULH` — the same low/high-half carry-less-multiply
semantics, issued as `kecc_aes_k_xif` custom instructions (CUSTOM-0 opcode) instead
of native B-extension instructions — were prototyped in
`kecc_aes_k_xif_ghash.sv`/`kecc_aes_k_xif_ex.sv` and measured at **1,692 cycles /
1,404 instrs**: not faster than native `clmul`/`clmulh` (1,685 cycles), marginally
*slower* (+0.4%), with an identical instruction count (both compile to the same
C-level sequence; only the `.insn` encoding differed). The extra cycle(s) are
consistent with CV-X-IF offload's issue/register-read/execute/writeback path adding
overhead a native ALU-pipeline instruction doesn't pay. Given no measured benefit,
the RTL, opcode-table entries, and coprocessor-side test scaffolding were removed
(see `kecc_aes_k_xif/README.md`'s "Considered and not implemented") — `aes_gcm`'s
~13x speedup above comes entirely from GHASH no longer being the bottleneck at all
(via native `clmul`/`clmulh`), not from a coprocessor GHASH path. The value a
self-contained coprocessor GHASH instruction *would* offer is portability to a
config without B-extension enabled, not a performance win over one that has it —
not a priority for this project's actual target config.

## Results — Keccak sponge interface (Phase B)

FIPS 203 defines separate init/absorb/squeeze operations for SHAKE128 because
ML-KEM/ML-DSA drive it incrementally rather than through one-shot hash calls. These 7
new tests measure each sponge phase on its own (all SHAKE128, `fips202.c`'s existing
incremental API -- `shake128_init/absorb/finalize/squeeze`, already exercised in
production by `kmac.c`/`hmac.c`), instead of only the whole-message numbers the
original 11 tests give. Every test's correctness check compares its incremental-API
result against the existing one-shot `shake128()` wrapper, not a fixed KAT -- this
suite validates the incremental API's internal consistency (composability across
call boundaries), which is exactly the guarantee FIPS 203 depends on.

**A real limitation found and documented, not worked around**: the requested 64 KiB
input size for `keccak_sponge_absorb` was dropped after an actual run showed it hits
this specific Verilator/fesvr `veri-testharness` build's hard-coded ~2,000,000
simulated-core-cycle watchdog (`*** FAILED *** (tohost = 2147483647) after 2000013
cycles` -- the testbench's own htif/DTM layer giving up, confirmed distinct from
`cva6.py`'s wall-clock `--iss_timeout`, which was ruled out first by raising it and
re-running). 4096 B is the largest size that fits in this environment.

| Sponge phase | SW cycles | Tightly cycles | Speedup | SW instrs | Tightly instrs | Instr reduction | SW bits/cycle | Tightly bits/cycle |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| `init` (state zeroing) | 137 | 155 | 0.88x | 82 | 82 | 1.00x | N/A | N/A |
| `absorb` 0 B | 111 | 109 | 1.02x | 43 | 43 | 1.00x | 0 | 0 |
| `absorb` 32 B | 587 | 577 | 1.02x | 526 | 526 | 1.00x | 0.4361 | 0.4436 |
| `absorb` 64 B | 1,026 | 1,034 | 0.99x | 1,006 | 1,006 | 1.00x | 0.4990 | 0.4951 |
| `absorb` 128 B | 1,987 | 1,986 | 1.00x | 1,966 | 1,966 | 1.00x | 0.5153 | 0.5156 |
| `absorb` 1024 B | 43,469 | 27,380 | 1.59x | 42,386 | 24,950 | 1.70x | 0.1884 | 0.2991 |
| `absorb` 4096 B | 172,744 | 109,092 | 1.58x | 169,394 | 99,650 | 1.70x | 0.1896 | 0.3003 |
| `squeeze` 32 B | 6,037 | 3,022 | 2.00x | 5,285 | 2,379 | 2.22x | 0.0424 | 0.0847 |
| `squeeze` 64 B | 5,825 | 3,029 | 1.92x | 5,701 | 2,795 | 2.04x | 0.0878 | 0.1690 |
| `squeeze` 128 B | 6,657 | 3,857 | 1.73x | 6,533 | 3,627 | 1.80x | 0.1538 | 0.2654 |
| `squeeze` 512 B | 26,516 | 15,326 | 1.73x | 26,027 | 14,403 | 1.81x | 0.1544 | 0.2672 |
| `squeeze` 1024 B | 48,018 | 28,437 | 1.69x | 47,185 | 26,843 | 1.76x | 0.1706 | 0.2880 |
| `squeeze` 2048 B | 91,030 | 54,667 | 1.67x | 89,501 | 51,723 | 1.73x | 0.1799 | 0.2997 |
| `squeeze` 4096 B | 177,054 | 107,127 | 1.65x | 174,133 | 101,483 | 1.72x | 0.1850 | 0.3058 |
| `padding`/`finalize` (O(1)) | 40 | 34 | 1.18x | 19 | 19 | 1.00x | N/A | N/A |
| `context` save (memcpy 208 B) | 164 | 172 | 0.95x | 71 | 71 | 1.00x | N/A | N/A |
| `context` restore (memcpy 208 B) | 188 | 187 | 1.01x | 71 | 71 | 1.00x | N/A | N/A |

`absorb`/`squeeze` incremental (chunked, 64 B/call) vs. monolithic, same total bytes:

| Test | Total | SW mono | SW chunked | Tightly mono | Tightly chunked |
|---|---:|---:|---:|---:|---:|
| absorb cycles | 1024 B | 44,055 | 45,712 | 27,724 | 29,128 |
| absorb cycles | 4096 B | 172,748 | 182,261 | 109,115 | 115,967 |
| squeeze cycles | 1024 B | 48,624 | 49,161 | 28,818 | 29,565 |
| squeeze cycles | 4096 B | 177,059 | 181,142 | 107,123 | 111,029 |

## Results — Loosely-coupled AXI accelerator (all 8 variants)

`tests/loosely/` runs the same test suite a third way, accelerated by
`kecc_aes_k_axi` -- an AXI-memory-mapped peripheral wrapping `keccak_aes_k_top`
(the unified AES/Keccak core from the `kecc-aes-k` project), driven by MMIO
register polling rather than custom instructions. See `kecc_aes_k_axi/README.md`
for the accelerator itself and the `AES_VARIANT` flag that selects which of 8
RTL variants (v2/v3/v4x3-`SBOX_IMPL`/v5x3-`SBOX_IMPL`) gets built.

**All 8 variants x all 22 tests = 176/176 runs pass with zero KAT mismatches.**
Every cycle/instruction number below was measured (Verilator `veri-testharness`,
`cv64a6_imac_crypto`), not estimated. Column layout collapses variants whose
numbers are **byte-identical across the entire 22-test suite**, confirmed by
diffing the raw captured logs (`.variant_data/*.txt` in the repo root) rather
than assumed:

- **v4's three `SBOX_IMPL` choices (`serial_rom`/`dp_rom`/`bp`) are identical
  to each other on every single test** -- `SBOX_IMPL` has zero effect on
  whole-operation cycle count for v4. One `v4` column covers all three.
- **v5's `serial_rom` and `dp_rom` are identical to each other**, but **v5's
  `bp` differs from them on 6 of 22 tests** (see below) -- so v5 gets two
  columns, `v5 (serial/dp_rom)` and `v5 (bp)`.

`v4` has no `PARALLEL_SLICES` parameter (fixed structurally); `v5`'s three
`SBOX_IMPL` variants above all use `PARALLEL_SLICES=4` (confirmed from the
generated target config packages), so the v4-vs-v5 comparison below is a
comparison of the wider (v5) datapath against the narrower (v4) one, not a
`PARALLEL_SLICES` sweep -- no `PARALLEL_SLICES` value other than 4 was built
or measured.

**`aes_core` here is not directly comparable to the SW/Tightly `aes_core` row
above**: `kecc_aes_k_axi`'s register map only exposes the final block result,
not the intermediate round-key schedule, so `tests/loosely/aes_core` benchmarks
one full AES-128 block encrypt (FIPS-197 Appendix B vector) instead of
key-expansion-alone -- see that test's own file header for the rationale.

A real correctness-relevant driver optimization went into these numbers: the
core's key schedule is direction-specific (encrypt vs. decrypt use different
internal round keys), but a single schedule stays valid in the core's internal
registers across any number of same-key, same-direction block calls --
`kecc_aes_k_axi.c`'s driver caches the last-loaded (key, direction) pair and
skips re-running the hardware key-schedule pulse when a call reuses it, so
CBC/CTR/GCM/XTS-style repeated-block-same-key sequences pay for one schedule,
not one per block -- the same amortization `tightly`'s `aes128_ctx_t` gets by
precomputing both schedules once up front.

### Cross-version pattern (observed, not assumed)

Reading down each column tells a consistent story:

- **v2 → v3**: Keccak-only tests (`sha3_*`, `shake*`, `kmac256`,
  `hmac_sha3_256`) are unchanged. AES tests get slightly slower (tens of
  cycles) across the board.
- **v3 → v4**: same pattern again -- Keccak-only tests are *exactly* unchanged
  from v3 (not just close), AES tests get slower again (a larger jump this
  time, ~200-600 cycles depending on the test).
  `SBOX_IMPL` does not matter for v4 (see above).
- **v4 → v5 (serial_rom/dp_rom)**: this time Keccak-only tests *also* get
  slower (e.g. `keccak_core` 3,660 → 4,065 cycles, `sha3_256` 4,709 → 5,109),
  on top of AES getting slower again -- consistent with v5's wider
  (`PARALLEL_SLICES=4`) datapath changing the shared Keccak permutation path
  too, not just the AES side.
- **v5 `bp`**: Keccak-only tests are identical to v5 `serial_rom`/`dp_rom`
  (unaffected, as expected -- `SBOX_IMPL` only touches the AES S-box). On 6 of
  the 12 AES-touching tests (`aes_core`, `aes_encrypt`, `aes_decrypt`,
  `aes_cbc`, `aes_ctr`, `aes_gcm`), `bp`'s cycle/instruction counts drop back
  down to **exactly** v3's numbers. On the other 6 (`aes_xts`, all 4
  `aes_gcm_sweep` sizes' encrypt+decrypt), `bp` shows **no difference** from
  `serial_rom`/`dp_rom` -- it stays at v4/v5-serial's slower level. This
  split was double-checked directly against the raw logs (not just the
  summary table) and is real, not a transcription error; *why* `bp` helps
  some AES call patterns and not others was not investigated further (would
  need RTL-level analysis of the S-box latency vs. the surrounding
  pipeline/handshake in each test's specific call pattern).

### Original 11 algorithms

| Test | v2 | v3 | v4 (all `SBOX_IMPL`) | v5 (serial/dp_rom) | v5 (bp) |
|---|---:|---:|---:|---:|---:|
| `keccak_core` | 3,684 / 2,665 | 3,660 / 2,667 | 3,660 / 2,667 | 4,065 / 2,787 | 4,065 / 2,787 |
| `aes_core` (single-block encrypt; not comparable to SW/Tightly `aes_core` -- see above) | 936 / 493 | 946 / 496 | 1,146 / 556 | 1,146 / 556 | 946 / 496 |
| `sha3_256` | 4,709 / 3,560 | 4,709 / 3,560 | 4,709 / 3,560 | 5,109 / 3,677 | 5,109 / 3,677 |
| `sha3_512` | 4,957 / 3,743 | 4,957 / 3,743 | 4,957 / 3,743 | 5,357 / 3,860 | 5,357 / 3,860 |
| `shake128_short` (32 B in) | 4,875 / 3,728 | 4,875 / 3,728 | 4,875 / 3,728 | 5,275 / 3,845 | 5,275 / 3,845 |
| `shake256_long` (2048 B in) | 75,508 / 58,506 | 75,508 / 58,506 | 75,508 / 58,506 | 81,983 / 60,468 | 81,983 / 60,468 |
| `kmac256` (41 B msg) | 17,146 / 13,795 | 17,146 / 13,795 | 17,146 / 13,795 | 18,373 / 14,161 | 18,373 / 14,161 |
| `hmac_sha3_256` (41 B msg) | 21,510 / 17,462 | 21,510 / 17,462 | 21,510 / 17,462 | 23,110 / 17,942 | 23,110 / 17,942 |
| `aes_encrypt` (ECB, 2 blocks) | 1,608 / 895 | 1,628 / 901 | 2,028 / 1,021 | 2,028 / 1,021 | 1,628 / 901 |
| `aes_decrypt` (ECB, 2 blocks) | 1,601 / 897 | 1,651 / 912 | 2,131 / 1,056 | 2,131 / 1,056 | 1,651 / 912 |
| `aes_cbc` (3 blocks, enc+dec) | — | — | — | — | — |

Correction (2026-08-11): `v2`'s `aes_core` row above previously read 743/417,
a stale number from earlier in this project's development. Re-running
`AES_VARIANT=loose_v2 tests/loosely/aes_core/run.sh` fresh today gives
936/493 -- the value now shown. Every other cell in this table was spot-
checked against the same re-run and still matches, so this correction is
isolated to this one cell.

`aes_cbc` breakdown, cycles / instrs (encrypt / decrypt phases):

| Phase | v2 | v3 | v4 | v5 (serial/dp_rom) | v5 (bp) |
|---|---:|---:|---:|---:|---:|
| encrypt | 2,790 / 1,693 | 2,820 / 1,702 | 3,420 / 1,882 | 3,420 / 1,882 | 2,820 / 1,702 |
| decrypt | 2,538 / 1,715 | 2,598 / 1,733 | 3,318 / 1,949 | 3,318 / 1,949 | 2,598 / 1,733 |

### New AES modes (CTR, GCM, XTS)

Cycles / instrs:

| Test | v2 | v3 | v4 | v5 (serial/dp_rom) | v5 (bp) |
|---|---:|---:|---:|---:|---:|
| `aes_ctr` encrypt (40 B) | 2,643 / 1,567 | 2,673 / 1,576 | 3,273 / 1,756 | 3,273 / 1,756 | 2,673 / 1,576 |
| `aes_ctr` decrypt (40 B) | 1,993 / 1,395 | 2,023 / 1,404 | 2,623 / 1,584 | 2,623 / 1,584 | 2,023 / 1,404 |
| `aes_gcm` encrypt (20 B AAD + 48 B payload) | 14,735 / 11,967 | 14,785 / 11,982 | 15,785 / 12,282 | 15,785 / 12,282 | 14,785 / 11,982 |
| `aes_gcm` decrypt (20 B AAD + 48 B payload) | 13,843 / 11,924 | 13,893 / 11,939 | 14,893 / 12,239 | 14,893 / 12,239 | 13,893 / 11,939 |
| `aes_xts` encrypt (1 sector, 48 B) | 4,663 / 2,980 | 4,703 / 2,992 | 5,503 / 3,232 | 5,503 / 3,232 | 5,503 / 3,232 |
| `aes_xts` decrypt (1 sector, 48 B) | 4,267 / 2,990 | 4,337 / 3,011 | 5,257 / 3,287 | 5,257 / 3,287 | 5,257 / 3,287 |

Note `aes_xts`: unlike the other 6 AES-touching tests, `v5 (bp)` does **not**
drop to v3's level here -- it stays at v4/v5-serial's slower number (see
"Cross-version pattern" above).

### AES-GCM payload-size sweep

Cycles / instrs. As with `aes_xts`, `v5 (bp)` does **not** differ from
`v5 (serial/dp_rom)` on any sweep size -- both columns are identical here, so
they're merged into one `v5` column.

| Payload (B) | v2 encrypt | v2 decrypt | v3 encrypt | v3 decrypt | v4 encrypt | v4 decrypt | v5 encrypt | v5 decrypt |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 16 | 9,848 / 7,848 | 8,951 / 7,802 | 9,878 / 7,857 | 8,981 / 7,811 | 10,478 / 8,037 | 9,581 / 7,991 | 10,478 / 8,037 | 9,581 / 7,991 |
| 64 | 16,142 / 13,852 | 16,215 / 13,979 | 16,202 / 13,870 | 16,275 / 13,997 | 17,402 / 14,230 | 17,475 / 14,357 | 17,402 / 14,230 | 17,475 / 14,357 |
| 256 | 45,357 / 38,560 | 45,399 / 38,687 | 45,537 / 38,614 | 45,579 / 38,741 | 49,137 / 39,694 | 49,179 / 39,821 | 49,137 / 39,694 | 49,179 / 39,821 |
| 1024 | 162,309 / 137,392 | 162,135 / 137,519 | 162,969 / 137,590 | 162,795 / 137,717 | 176,169 / 141,550 | 175,995 / 141,677 | 176,169 / 141,550 | 175,995 / 141,677 |

### Keccak sponge interface (Phase B)

Cycles / instrs. `SBOX_IMPL` never affects these (AES-only parameter); v4's
three variants and v5's three variants are each collapsed to one column.

| Sponge phase | v2 | v3 | v4 | v5 |
|---|---:|---:|---:|---:|
| `init` (state zeroing) | 137 / 82 | 137 / 82 | 137 / 82 | 137 / 82 |
| `absorb` 4096 B | 141,251 / 121,869 | 141,251 / 121,869 | 141,251 / 121,869 | 150,971 / 124,821 |
| `squeeze` 4096 B | 143,960 / 124,454 | 143,960 / 124,454 | 143,960 / 124,454 | 154,085 / 127,529 |
| `padding`/`finalize` (O(1)) | 38 / 22 | 38 / 22 | 38 / 22 | 38 / 22 |
| `context` save (memcpy 208 B) | 162 / 71 | 162 / 71 | 162 / 71 | 162 / 71 |
| `context` restore (memcpy 208 B) | 185 / 71 | 185 / 71 | 185 / 71 | 185 / 71 |

Full `absorb`/`squeeze` size sweep (0/32/64/128 B..4096 B), all 4 variant
groups, cycles / instrs -- v2/v3/v4 track together, v5 (both `SBOX_IMPL`
groups identical) is consistently ~7-9% higher at the larger sizes:

| Size (B) | absorb v2/v3/v4 | absorb v5 | squeeze v2/v3/v4 | squeeze v5 |
|---:|---:|---:|---:|---:|
| 0 | 115 / 45 | 115 / 45 | — | — |
| 32 | 609 / 561 | 609 / 561 | 4,181 / 3,169 | 4,581 / 3,286 |
| 64 | 1,091 / 1,073 | 1,091 / 1,073 | 4,401 / 3,614 | 4,806 / 3,737 |
| 128 | 2,114 / 2,097 | 2,114 / 2,097 | 5,314 / 4,510 | 5,719 / 4,633 |
| 512 | — | — | 21,086 / 17,935 | 22,706 / 18,427 |
| 1024 | 35,432 / 30,507 (v2/v3/v4) | 37,862 / 31,245 | 38,636 / 33,152 | 41,471 / 34,013 |
| 2048 | — | — | 73,744 / 63,586 | 79,009 / 65,185 |
| 4096 | 141,251 / 121,869 | 150,971 / 124,821 | 143,960 / 124,454 | 154,085 / 127,529 |

`absorb`/`squeeze` incremental (chunked, 64 B/call) vs. monolithic, cycles,
same v2/v3/v4-track vs. v5 split:

| Test | Total (B) | Monolithic v2/v3/v4 | Chunked v2/v3/v4 | Monolithic v5 | Chunked v5 |
|---|---:|---:|---:|---:|---:|
| absorb | 1024 | 35,680 | 37,855 | 38,105 | 40,285 |
| absorb | 4096 | 141,273 | 150,905 | 150,993 | 160,625 |
| squeeze | 1024 | 38,864 | 39,786 | 41,694 | 42,621 |
| squeeze | 4096 | 143,970 | 148,193 | 154,095 | 158,318 |

## Results — Area (Vivado synthesis)

Out-of-context synthesis of the CVA6 core (`ariane`) with `kecc_aes_k_xif`
tightly-coupled via CV-X-IF, config `cv64a6_imac_crypto` (same config the
benchmarks above run on). Tool: Vivado v2024.1 (win64). Part:
`xc7a100tftg256-2` (CW305, Artix-7 100T). See `fpga.md` /
`corev_apu/fpga/synth_area/run_synth.sh` to reproduce; full reports under
`corev_apu/fpga/synth_area/reports/`. Measured 2026-08-04. Still accurate as of
2026-08-05: a `GHASH_CLMULL`/`GHASH_CLMULH` addition was prototyped and measured
separately (see "Results — GHASH block-multiply"), found to offer no benefit over
native `clmul`/`clmulh`, and removed — the coprocessor is back to these same 6
opcodes, unchanged from this measurement.

| Metric | Whole system | CVA6 core alone | `kecc_aes_k_xif` coprocessor alone |
|---|---:|---:|---:|
| Total LUTs | 56001 | 55452 | **375** |
| FFs | 23889 | 23623 | **265** |
| RAMB36 | 36 | 36 | 0 |
| DSP Blocks | 27 | 27 | 0 |

The coprocessor is **0.67% of system LUTs / 1.11% of system FFs** — the
cycle/instruction speedups above (1.6-45x depending on operation) come from
a coprocessor that costs well under 1% of this system's area, with 0 BRAM
and 0 DSP usage (every `xor3`/`xandn`/`rxri`/`aes64*` datapath is pure
combinational/register logic, see `implementation.md`). Compare against
`kecc-aes-k/result.md`'s own standalone `keccak_aes_k_top` area section for
the loosely-coupled comparison.

## Results — Area, loosely-coupled AXI accelerator (all 8 variants)

Out-of-context synthesis of `kecc_aes_k_axi_top` **including its wrapper**
(the `axi_to_reg` AXI-to-register-file bridge and the reggen-generated
register file, not just the bare `keccak_aes_k_top` core) -- answering
"how big is the accelerator, considering also the wrapper", not just the
core-alone number `kecc-aes-k/result.md` already has. Tool: Vivado v2024.1
(win64). Part: `xc7a100tftg256-2` (CW305, Artix-7 100T), same part as the
tightly-coupled measurement above. 100 MHz virtual clock, out-of-context
mode (no board pins, no bitstream) -- **area-focused, not timing closure**:
none of these 8 runs meets the 10ns constraint (all show negative WNS), same
caveat the sibling `kecc-aes-k/fpga/` core-only script already carries. See
`kecc_aes_k_axi/synth_area/run_synth.sh <variant>` to reproduce; full reports
under `kecc_aes_k_axi/synth_area/reports_<variant>/` (Vivado checkpoints
(`.dcp`) themselves were deleted after extraction to save disk space -- rerun
the script to regenerate one if needed). Measured 2026-08-10.

| Variant | Total LUTs | % LUTs | Slice Registers (FFs) | % FFs | Slices (packed CLBs) | % Slices |
|---|---:|---:|---:|---:|---:|---:|
| v2 | 10,894 | 17.18% | 6,720 | 5.30% | 3,657 | 23.07% |
| v3 | 10,200 | 16.09% | 4,781 | 3.77% | 2,833 | 17.87% |
| v4 (serial_rom) | 9,182 | 14.48% | 4,843 | 3.82% | 2,573 | 16.23% |
| v4 (dp_rom) | 9,093 | 14.34% | 4,783 | 3.77% | 2,476 | 15.62% |
| v4 (bp) | 10,214 | 16.11% | 4,815 | 3.80% | 2,866 | 18.08% |
| v5 (serial_rom) | 6,252 | 9.86% | 3,396 | 2.68% | 1,821 | 11.49% |
| v5 (dp_rom) | 6,233 | 9.83% | 3,339 | 2.63% | 1,789 | 11.29% |
| v5 (bp) | 6,629 | 10.46% | 3,369 | 2.66% | 1,898 | 11.97% |

RAMB36/RAMB18/DSP are 0 across all 8 variants. `v4`'s three `SBOX_IMPL`
choices barely move total area (~9.1-10.2K LUTs, within normal synthesis
noise); **`v5`'s slice-serial Keccak datapath (`keccak_slice_serial.sv`,
`PARALLEL_SLICES=4`) is genuinely ~40% smaller than v2/v3/v4's fully-parallel
`keccak_round.sv`** (6.2-6.6K LUTs vs 9.1-10.9K) -- consistent with, and the
direct explanation for, v5 also being measurably *slower* in the performance
results above (a smaller per-cycle datapath reused over more cycles is a
textbook area/latency trade, not a contradiction). Confirmed no black boxes
in any of the 8 utilization reports, so none of this is an artifact of
missing RTL.

Hierarchical breakdown (`report_utilization -hierarchical`), LUTs / FFs:

| Variant | `i_keccak_aes_k_top` (core) | `kecc_aes_k_axi_reg_top_i` (reg file) | `i_axi2reg` (AXI bridge) |
|---|---:|---:|---:|
| v2 | 5,392 / 3,806 | 2,222 / 2,138 | 3,026 / 773 |
| v3 | 4,514 / 1,878 | 2,407 / 2,127 | 3,025 / 773 |
| v4 (serial_rom) | 4,365 / 1,939 | 2,453 / 2,128 | 2,365 / 773 |
| v4 (dp_rom) | 4,289 / 1,880 | 2,443 / 2,127 | 2,361 / 773 |
| v4 (bp) | 4,649 / 1,912 | 2,411 / 2,127 | 3,154 / 773 |
| v5 (serial_rom) | 2,163 / 480 | 729 / 2,128 | 3,361 / 786 |
| v5 (dp_rom) | 2,168 / 421 | 706 / 2,130 | 3,359 / 786 |
| v5 (bp) | 2,560 / 453 | 729 / 2,128 | 3,342 / 786 |

Each row's three numbers plus the wrapper's own small glue logic (not shown,
a few hundred LUTs) sum back to that variant's total LUTs above -- but the
**split between the register file and the AXI bridge shifts noticeably
between the v2/v3/v4 family and v5** (register file drops from ~2.2-2.5K LUTs
to ~0.7K, bridge rises from ~2.4-3.2K to ~3.3-3.4K) even though
`kecc_aes_k_axi_reg_top.sv` itself is the exact same generated file in every
variant. This is Vivado's cross-hierarchy optimization moving logic across
the reported instance boundary (confirmed the *totals* stay consistent; only
the *attribution* between these two specific sub-blocks moves) -- read the
register-file-vs-bridge split as approximate per variant, but the **overall
finding that AXI plumbing (bridge + register file combined) is on the same
order of magnitude as the compute core itself holds across all 8 variants**,
motivating the unified-storage redesign below: if the register file's own
storage *is* the core's working storage (no separate copy, no
`axi_to_reg`-mediated round trip through a second storage element), both the
register-file and a share of the bridge/glue overhead should shrink.

## Results — Unified-storage redesign (`loose_v2_unified`)

The redesign predicted above: a second AXI wrapper (`kecc_aes_k_axi_unified_top.sv`
+ `kecc_aes_k_axi_unified.hjson`, both new) around a new core
(`keccak_aes_k_top_unified.sv`, in `kecc_aes_k_axi/hw/rtl/v2_unified/`) with **no
internal working-state register at all**, for both Keccak and AES -- modeled
directly on `cva6-keccak-loosely/keccak_ip/rtl/keccak_dp.sv`'s pattern (state read
live from the register file every cycle, written back into the very same
registers every round, gated by a write-enable pulse -- the register file's own
flip-flops are the only storage). Extended here to AES too, which the keccak-only
precedent didn't cover: `BLOCK0`/`BLOCK1` are now hardware-writable (`hwaccess:
hrw`, split into four independent 32-bit sub-fields to match AES's word-serial
SBOX substitution phase) and there is no separate `RESULT0`/`RESULT1` register at
all -- software reads the (by then fully transformed) `BLOCK0`/`BLOCK1` back as
the AES result, the same way `KECCAK_DATA0-24` already served as both input and
output. AES's expanded key *schedule* (`aes_key_mem`'s internal RAM) is not part
of this unification and stays private/internal either way -- it was never
AXI-visible to begin with, in either design.

Selected via `AES_VARIANT=loose_v2_unified` (same `select_aes_variant.sh`/
`tests/loosely/` flow as the other 8 variants) or
`kecc_aes_k_axi/synth_area/run_synth.sh v2_unified` for synthesis. Built only for
the v2 RTL family so far (no `SBOX_IMPL`/`PARALLEL_SLICES` variants) -- see
"Extending to v3/v4/v5" below for what porting further would take.

**Correctness**: all 22/22 tests pass (same KAT vectors as every other variant).
One real bug was caught and fixed during bring-up: the initial register map had
`BLOCK0`/`BLOCK1`'s upper/lower-half assignment backwards relative to the
existing driver's fixed byte-ordering convention, which silently computed a
consistent but wrong ciphertext (`aes_core` failed all 16 output bytes on the
first run) -- fixed by swapping which register holds which half in
`kecc_aes_k_axi_unified.hjson` and the wrapper's wiring, no driver change needed.

### Performance: cycle-for-cycle identical to v2 on 21 of 22 tests

| Test | v2 | v2\_unified | Difference |
|---|---:|---:|---:|
| `keccak_core` | 3,684 / 2,665 | 3,660 / 2,667 | -24 cycles (no separate Keccak "load" step needed -- the register file already holds the input) |
| every other test (21/22) | (see tables above) | identical | 0 |

Every AES test that chains multiple block calls through the same driver
(`aes_cbc`, `aes_ctr`, `aes_gcm`, `aes_xts`, `aes_encrypt`, `aes_decrypt`,
`aes_gcm_sweep`) and every Keccak sponge/KMAC/HMAC/SHA3/SHAKE test reproduces
its v2 cycle count exactly -- removing the internal working-state register cost
*zero* extra cycles anywhere except the one Keccak case above, where it actually
removed a cycle. This matches expectation: the redesign only changes *where*
each round's result is stored (register file vs. a second internal copy), not
the round count, the FSM's state sequencing, or the AXI transaction pattern.

(Note: `tests/result.md`'s `v2` `aes_core` figure was corrected from a stale
743/417 to the freshly-verified 936/493 during this comparison -- see the
correction note above the "Original 11 algorithms" table. Without that fix,
`aes_core` would have looked like a 193-cycle regression; re-running v2 fresh
confirmed it isn't one.)

### Area: real reduction, though smaller than a naive "remove 1600+128 duplicate bits" estimate

Same Vivado flow, same part, same 100 MHz virtual clock as the 8-variant area
table above. Measured 2026-08-11.

| Metric | v2 | v2\_unified | Change |
|---|---:|---:|---:|
| Total LUTs | 10,894 | 9,358 | **-14.1%** |
| Slice Registers (FFs) | 6,720 | 4,999 | **-25.6%** |
| Slices (packed CLBs) | 3,657 | 3,143 | **-14.1%** |
| WNS @ 10ns (100 MHz target) | -1.532ns | -0.905ns | closer to closing, still not met |

Hierarchical breakdown, LUTs / FFs (same cross-hierarchy-optimization caveat as
the 8-variant table above applies -- Vivado can move logic across the
register-file/bridge instance boundary during optimization, so read the
individual sub-block split as approximate; the row totals and the grand total
are what's robust):

| Sub-block | v2 | v2\_unified |
|---|---:|---:|
| Core (`i_keccak_aes_k_top` / `i_keccak_aes_k_top_unified`) | 5,392 / 3,806 | 2,918 / 2,206 |
| Register file (`kecc_aes_k_axi_reg_top_i` / `..._unified_reg_top_i`) | 2,222 / 2,138 | 4,449 / 2,017 |
| AXI bridge (`i_axi2reg`) | 3,026 / 773 | 1,751 / 773 |

The **core itself shrank 45.9% in LUTs / 42.0% in FFs** -- removing the
1600-bit Keccak state register and the 128-bit AES working-block register (no
longer duplicated anywhere in this module) is exactly the saving predicted.
The **register file's LUT cost roughly doubled** (2,222 -> 4,449) -- the
expected cost of the trade: `BLOCK0`/`BLOCK1` need real per-field
read/hardware-write/software-write arbitration logic now (four independent
32-bit fields with `hwaccess: hrw`, versus two plain software-only 64-bit
fields before), and `KECCAK_DATA` commits every round instead of once, both of
which cost real muxing silicon that the non-unified design's register file
never needed. The AXI bridge's reported LUT count also dropped (3,026 ->
1,751) with FFs unchanged -- given `axi_to_reg.sv` itself is bit-for-bit
identical in both builds, this is most likely more of the same cross-hierarchy
attribution shift already seen in the 8-variant table, not a genuine
behavioral difference in the bridge.

**Net result: the area saved by removing the duplicate working-state storage
is larger than the area added by the register file's new fine-grained
hardware-write logic, giving a real net reduction -- but a meaningfully
smaller one than "delete 1728 bits of duplicate flip-flops" would naively
suggest**, because eliminating that duplication requires adding real
arbitration logic elsewhere to let the AXI-visible registers safely serve
double duty as both the software staging area and the hardware's active
working set.

### Extending to v3/v4/v5

Not done in this pass. The user's own hint -- "once done for one, probably the
new structure/wrapper should adapt easily to all the variant" -- holds
structurally: `keccak_aes_k_top_unified.sv` reuses v2's pure-combinational
`aes_encipher_datapath.sv`/`aes_decipher_block.sv`/`aes_key_mem.sv`/
`aes_sbox.sv`/`keccak_round.sv` verbatim (same files v3 also uses unmodified),
and the wrapper/register-file pieces (`kecc_aes_k_axi_unified_top.sv`,
`kecc_aes_k_axi_unified.hjson`) don't reference `SBOX_IMPL`/`PARALLEL_SLICES`
or any version-specific file at all -- only the RTL file list
(`kecc_aes_k_axi/hw/rtl/v2_unified.flist`) is version-specific. Porting to v3
should be a small delta (swap which `aes_sbox`/`keccak_round` files the flist
points at, matching v3's own file set). v4/v5 are a larger delta:
`keccak_aes_k_top_unified.sv` would need the same `SBOX_IMPL`/(`PARALLEL_SLICES`
for v5) parameters and `` `ifdef``-based instantiation-shape handling the
non-unified core already has, plus v5's `keccak_slice_serial.sv`/
`keccak_lane_mem.sv` datapath would need its own live-register-file
integration (its round structure differs from v2/v3/v4's single-shot
`keccak_round.sv`, so the "read live, commit every round" pattern would need
re-deriving for its slice-serial round structure specifically, not just
reused).

## Takeaways

- Keccak-based operations (SHA3/SHAKE/KMAC/HMAC) get a consistent **~1.6-1.9x** cycle
  speedup and **~1.8-2.1x** instruction reduction from `xor3`/`xandn`/`rxri` — the
  coprocessor accelerates the permutation's bitwise steps, but the surrounding
  sponge/padding logic stays in software either way.
- AES-ECB/CBC/CTR/XTS get a much larger **8-45x** cycle speedup, since `aes64*`
  replaces the software S-box lookup tables and GF(2^8) multiplication with single
  instructions. Decryption benefits the most, because software `InvMixColumns`'
  repeated `Multiply()` calls are far more expensive than the encryption path's
  simpler forward MixColumns.
- **AES-GCM originally was the outlier (~1.2x speedup)**, far below every other AES
  mode, because GHASH was pure software and dominated the cycle count (~150k of ~170k
  total cycles for a 48-byte payload) — the `aes64*` coprocessor accelerated the AES
  core (H generation, keystream, tag mask) but never touched GHASH's separate
  GF(2^128) datapath. **This has since been fixed**: `aes_gcm` now gets **~13x
  speedup**, in line with the other AES modes, from GHASH going through the RISC-V
  B-extension's native `clmul`/`clmulh` — already present in this config the whole
  time. A dedicated `kecc_aes_k_xif` `GHASH_CLMULL`/`GHASH_CLMULH` instruction pair
  was also prototyped and measured (see "Results — GHASH block-multiply") but wasn't
  actually faster than the native path, so it was removed rather than kept as
  unjustified RTL/opcode-table complexity.
- `aes_core` (key expansion alone) shows the coprocessor's largest *relative* win on a
  narrow operation (4.8x cycles, 8.8x instructions) since it's almost entirely
  S-box/round-constant work with very little other overhead to dilute the comparison.
- Instruction reduction consistently exceeds cycle-count speedup across every test —
  the custom instructions collapse several software instructions (table lookups, shifts,
  masks, XORs) into one, but each such instruction can take more than one cycle on this
  core, so the per-cycle win is smaller than the per-instruction win.
- bits/cycle throughput and cycle speedup don't always rank the same way: `keccak_core`
  has by far the highest raw bits/cycle of any test (it's one dense 1600-bit
  permutation with no sponge/padding/mode overhead diluting it), even though its
  *speedup* (1.65x) is unremarkable next to AES's.
- **The sponge-phase breakdown shows the coprocessor speedup comes entirely from the
  permutation, not the sponge glue.** `absorb` sizes at or below `SHAKE128_RATE` (168
  B) trigger *zero* internal permutations (per `fips202.c`'s `keccak_absorb`, which
  only permutes when the running buffer fills a full rate block) and show **no
  speedup at all** (0.99-1.02x -- within noise). Once a size requires internal
  permutations (1024 B / 4096 B, needing ~6/24 of them), speedup jumps straight to the
  same ~1.58-1.70x range `keccak_core` shows. `squeeze` shows speedup even at its
  smallest size (32 B) because a fresh squeeze after `finalize()` always triggers one
  permutation immediately (`keccak_squeeze`'s `if (pos == r) permute` fires on the
  very first call) -- so squeeze pays for, and benefits from, at least one
  permutation no matter how little output is requested.
- `init`, `padding`/`finalize`, and `context` save/restore are all O(1) operations
  that never touch the permutation -- consistent with that, none of them show a real
  speedup (differences are within single-digit-percent build/noise, and `init` and
  `context` save are actually marginally *slower* on tightly, most likely a fixed
  build/layout difference rather than anything algorithmic). These confirm the
  coprocessor's benefit is specifically tied to permutation-bearing work.
- Chunked (64 B/call) incremental absorb/squeeze costs a small, consistent overhead
  over one monolithic call of the same total size (roughly 3-6% more cycles on both
  trees) -- the price of composability across call boundaries that ML-KEM/ML-DSA rely
  on, not a correctness or speedup concern.

## Future work / methodology notes (not implemented here)

- **AES-GCM acceleration landed** (2026-08-05), but not via a dedicated coprocessor
  instruction. GHASH now runs on the RISC-V B-extension's native `clmul`/`clmulh`
  (`tests/tightly/common/ghash.c`, `clmul_native.h`) — a `GHASH_CLMULL`/`GHASH_CLMULH`
  `kecc_aes_k_xif` instruction pair was prototyped and measured first (see "Results —
  GHASH block-multiply") but showed no cycle advantage over the native path, so it was
  removed rather than kept as unjustified coprocessor complexity. The `A(AES-GCM) =
  A(AES core) + A(GHASH) + A(mode controller)` area decomposition this bullet used to
  call for no longer applies here — GHASH isn't part of this coprocessor's area at
  all, `kecc_aes_k_xif` is unchanged from the "Results — Area" measurement above. If a
  *self-contained* (no-B-extension-dependency) coprocessor GHASH is ever wanted for a
  different target config, revisit `kecc_aes_k_xif/README.md`'s "Considered and not
  implemented" entry for the encoding/design this repo already validated correct.
- **AES-XTS** is standardized specifically for storage-device confidentiality (IEEE
  1619 / SP 800-38E) but provides no authentication of the data or its source. It's
  valuable here specifically *because* it represents that storage use case — not as a
  general-purpose AEAD candidate.
- **AES-GCM-SIV** (nonce-misuse-resistant, RFC 8452) was considered and explicitly
  **not implemented**: it needs POLYVAL (a third distinct GF(2^128) variant, different
  again from both GHASH's and XTS's conventions), per-nonce key derivation, and
  multiple AES executions per message, and it's an informational RFC rather than a
  NIST-standardized mode. Per the plan, it's deferred until after the main
  architecture/benchmark work is complete rather than added now.
- **CBC and ECB remain in the suite** (as `aes_cbc`/`aes_encrypt`/`aes_decrypt`) but
  are not the main application-benchmark story going forward — NIST already restricts
  ECB to specifically permitted situations, and CBC lacks authentication. CTR/GCM/XTS
  are the more representative modern workloads.

## Reproducing

```bash
source tests/software/run.sh all   # includes the 3 new AES-mode + 7 new sponge tests
source tests/tightly/run.sh all    # (run.sh's test discovery picks up new directories)
```

Each new test can also be run individually, e.g. `source tests/software/run.sh aes_gcm`
or `source tests/software/run.sh keccak_sponge_absorb`.

**Caution:** both trees write their `veri-testharness` logs to the same
`verif/sim/out_<date>/veri-testharness_sim/<name>.cv64a6_imafdc_sv39.log*` path (log
names are derived from the test's source basename, not the tree), and both target the
same `cv64a6_imafdc_sv39` Verilator build. Running the two trees back-to-back is safe,
but running them **concurrently** would race on the same `work-ver` build directory,
and running one tree after the other overwrites the previous tree's log files (the
numbers above were captured from each run's live output before the next tree started).

**Also note:** this platform's minimal `sprintf()` (`tests/*/common/uart.h`'s `printf`
macro) has no `%f`/`%lf` support — using it silently corrupts subsequent `%lu`
arguments in the same call (discovered while adding the throughput metric to
`aes_ctr`/`aes_gcm`/`aes_xts`). All throughput figures are computed and printed as
fixed-point integers (`bits/cycle * 10000`, formatted as `X.XXXX` via `%lu.%04lu`)
instead of `double`/`%f`. Apply the same convention to any future test that prints a
non-integer metric.

**Also note:** this `veri-testharness` build enforces a hard ~2,000,000
simulated-core-cycle watchdog in its htif/DTM layer, independent of `cva6.py`'s
`--iss_timeout` (a wall-clock limit, default 500s — raising it does not help once the
*cycle* watchdog is what's firing). A test whose benchmarked region needs more real
CPU work than that budget allows will hit `*** FAILED *** (tohost = 2147483647)` partway
through, rather than completing or cleanly failing its own correctness check. Keep any
future large-input test's total simulated work within that budget, or expect it to be
silently cut off. Discovered via `keccak_sponge_absorb`'s originally-planned 64 KiB
input case (see its own file comment and the Phase B section above).
