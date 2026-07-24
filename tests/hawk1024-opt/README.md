# hawk1024-opt — HAWK-1024 with CVA6 hardware acceleration

This is `tests/hawk1024/` (the plain, pure-software HAWK-1024 KAT) with the
Keccak-AXI (`keccak_ip/rtl/keccak_f.sv`/`keccak_dma_ctrl.sv`) and
`ntt_engine.sv` (`keccak_ip/rtl/ntt_engine.sv`) accelerators wired in,
following the exact same dispatcher pattern originally built and verified
for HAWK-256 (`NTT_ACCEL_DESIGN.md`). Every call site keeps calling the
same function names it always did (`mp_NTT()`, `vect_FFT()`, etc.) —
each is now a transparent dispatcher that redirects to hardware above a
small size threshold and falls back to the original software path below
it, so no caller (`ng_hawk.c`, `ng_ntru.c`, `ng_poly.c`) needed to change.

## Run

```
bash tests/hawk1024-opt/run.sh
```

`TEST_KEY` (KeyGen) defaults to 1 (enabled) in `main.c`, matching every
other variant's convention — be aware HAWK-1024's pure-software KeyGen
baseline is ~226M cycles (`HAWK.md`), so a full KAT run (even
hardware-accelerated) is a long cycle-accurate RTL simulation. Pass
`-DTEST_KEY=0` via a temporary build-flag override to check Sign+Verify
only if you need a fast turnaround.

## Files changed vs. `tests/hawk1024/`, and what replaced what

| File | Lines (this directory) | What was substituted |
|---|---|---|
| `sha3.c` | 10, 618–946 | Keccak-F1600 permutation (`process_block`) redirected to the Keccak-AXI peripheral; SHAKE state made hardware-resident (`shake_clone`/`shake_inject`/etc. now poke registers instead of running the permutation in software) |
| `sha3.h` | 21, 34–42 | Declarations for the hardware-resident SHAKE context additions above |
| `hawk_sign.c` | 2, 10–89 | `sig_gauss()`'s per-block squeeze offload to `gauss_sampler.sv` (`sig_gauss_hw_job()`) — **guarded by `logn==8`, so inert here**; HAWK-1024's Gaussian sampling still runs entirely in software (see "Not accelerated" below) |
| `hawk_vrfy.c` | 2–29, 505–599, 604, 666–690, 696–698, 702, 806–878 | `mp_NTT`/`mp_iNTT` (Verify's own private copy, used by `vrfy_ntt_norm`) and `mp_NTT_autoadj`'s reduced-butterfly phase, both redirected to `ntt_engine.sv` |
| `ng_mp31.c` | 2–15, 554–637, 640, 737–758, 761, 857–875 | `mp_NTT`/`mp_iNTT` (the real, exported symbols used by KeyGen/Sign — `ng_hawk.c`, `ng_ntru.c`, `ng_poly.c`), redirected to `ntt_engine.sv` |
| `ng_fxp.c` | 2–16, 1250–1311, 1314, 1511–1513, 1516, 1617–1648 | `vect_FFT`/`vect_iFFT` (the fixed-point transform behind `solve_NTRU_intermediate`'s `babai_loop` and `ng_hawk.c`'s constant-term check), redirected to `ntt_engine.sv` Revision 3 (fixed-point FFT mode) |
| `main.c` | 57–96, 152–155, 166–167, 204–205, 216 | Added hardware-dispatch cycle accounting/reporting (`ntt_dispatch_cycles`, `fft_dispatch_cycles`, `vrfy_ntt_dispatch_cycles`) — printed after `Keygen OK`/`Verify OK`, answers "how much of this phase was actually spent in a hardware call" |

## Not accelerated (stays software)

- **Gaussian sampling** (`sig_gauss()`, `hawk_sign.c`). `gauss_sampler.sv`'s
  CDT (cumulative distribution table) values are hardcoded in RTL for
  HAWK-256's specific sigma parameter (see that file's own header
  comment: "for HAWK-256 (n=256) only"). HAWK-1024 uses a different sigma
  and needs different CDT values — real, separate RTL work, explicitly
  out of scope for this pass. The `sig_gauss_hw_job()` call site already
  present in this file is guarded by `if (logn == 8)`, which is never
  true here, so it's dead code for this variant — kept only because
  `hawk_sign.c` is otherwise identical to the HAWK-256 source it was
  copied from, not because it does anything.
- **`fx32_FFT`/`fx32_iFFT`** (`hawk_vrfy.c`, Verify's `RebuildS0`
  fixed-point transform). A structurally different fixed-point format
  (Q1.31, `uint32_t`, table `FX32_GM`) from `ng_fxp.c`'s `vect_FFT`
  (Q32.32, `fxr`, table `GM_TAB`) — different word width, different
  twiddle table, different butterfly formula. `ntt_engine.sv`'s FFT mode
  cannot serve it without a second, separate hardware datapath. See
  `NTT_ACCEL_DESIGN.md`'s "Fixed-point FFT scoping" section. Measured (on
  HAWK-256) at 15.5% of Verify — a real, separately-scoped opportunity,
  not touched here.

## Non-cacheable DRAM scratch windows

The hardware writes results back as a second AXI master, bypassing the
CPU's D$; each accelerator therefore stages its buffer through a fixed,
non-cacheable DRAM window (same convention as `GAUSS_HW_SCRATCH_ADDR`)
rather than relying on `fence` for coherency (this SoC's
`DcacheFlushOnFence`/`DcacheInvalidateOnFlush` are both 0). Sized for
HAWK-1024 (n≤1024), and kept non-overlapping so KeyGen/Sign/Verify's
scratch use never aliases even though they never run concurrently in
this KAT:

| Window | Address | Size | Used by |
|---|---|---|---|
| `GAUSS_HW_SCRATCH_ADDR` | `0x80F00000` | 512B | `hawk_sign.c` (inert here) |
| `NTT_HW_SCRATCH_ADDR` (Verify) | `0x80F01000` | 4096B (n×4) | `hawk_vrfy.c` |
| `NTT_HW_SCRATCH_ADDR` (KeyGen/Sign) | `0x80F03000` | 4096B (n×4) | `ng_mp31.c` |
| `FFT_HW_SCRATCH_ADDR` | `0x80F05000` | 8192B (n×8) | `ng_fxp.c` |

## Provenance

`sha3.c`/`sha3.h`/`hawk_sign.c` (Keccak-AXI wiring) were already present
in this directory before this port (carried over from `hawk-1024-keccak`,
this directory's previous name). `hawk_vrfy.c`, `ng_mp31.c`, `ng_fxp.c`,
and `main.c`'s dispatcher/accounting additions were ported from
`tests/hawk-256-keccak` in this pass — the underlying NTT/FFT algorithm
code is prime- and degree-generic (verified byte-identical to
`tests/hawk-256`'s copies before hardware redirection), so porting was a
direct copy plus scratch-window address/size adjustment for HAWK-1024,
not a re-derivation.
