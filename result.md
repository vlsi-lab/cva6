# Falcon Verify — Baseline vs. Hardware-Accelerated

Cycle counts for the `verify` phase only (`./run.sh verify`), measured via the
RISC-V `mcycle` CSR on the CVA6 `cv64a6_imac_crypto` target (Verilator
`veri-testharness` RTL simulation), single KAT vector (`N_KAT=1`).

- **Baseline** = `tests/pqc/baseline/falcon{512,1024}` — reference PQClean-style
  software implementation, no hardware offload.
- **Accelerated** = `tests/pqc/optimized/falcon{512,1024}` — SHAKE256/Keccak-F1600
  offloaded to the Keccak AXI accelerator, plus NTT/iNTT hardware dispatch and
  an optimized rejection sampler in the verify path.

## Results

| Algorithm    | Baseline (cycles) | Accelerated (cycles) | Cycles saved | Speedup |
| ------------ | -----------------: | --------------------: | ------------: | ------: |
| Falcon-512   |            473,803 | 229,864               |      243,939 |  2.061× |
| Falcon-1024  |            989,155 | 491,048               |      498,107 |  2.014× |

> **Speedup definition:** baseline cycle count ÷ accelerated cycle count.

## Source logs

| Algorithm / config    | Log                                                                                   |
| ---------------------- | -------------------------------------------------------------------------------------- |
| Falcon-512 accelerated | `verif/sim/out_2026-08-03/veri-testharness_sim/falcon512_optimized.cv64a6_imac_crypto.log.iss` |
| Falcon-1024 baseline    | `verif/sim/out_2026-08-03/veri-testharness_sim/falcon1024_baseline.cv64a6_imac_crypto.log.iss` |
| Falcon-1024 accelerated | `verif/sim/out_2026-08-03/veri-testharness_sim/falcon1024_optimized.cv64a6_imac_crypto.log.iss` |

## Caveats

- **Falcon-512 baseline (473,803 cycles) is not from today's run.** Today's
  `falcon512_baseline.cv64a6_imac_crypto.log.iss` has no `Clock cycles [verify]`
  line — it recorded 9,765,283 total RTL cycles (10–40× the other three runs)
  and ~20.7 CPU-minutes, consistent with a stale/interrupted `keygen+sign+verify`
  ("all") run rather than a clean, isolated `verify` run, so no reliable verify-only
  number could be read from it. The value used here is carried over from this
  repo's existing `results.md` (prior session); it was not re-measured today.
  It lines up closely with today's other three numbers versus their prior-session
  counterparts (all within ~0.1%), so it's very likely still accurate, but it
  should be re-verified with a clean `./tests/pqc/baseline/falcon512/run.sh verify`
  run before being relied on for anything precision-sensitive.
- All three fresh numbers (Falcon-512 accelerated, Falcon-1024 baseline,
  Falcon-1024 accelerated) matched this repo's pre-existing `results.md` fully-optimized
  figures (230,116 / 490,765) and baseline figure (989,144) within ~0.1%,
  cross-confirming both today's measurements and the prior ones.
- Single KAT vector per run (`N_KAT=1`); not averaged across multiple vectors.
