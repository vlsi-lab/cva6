# Keccak + AES64 Accelerator IP (kecc_aes_k_xif)
WIP...

## Directory tree
WIP...

## Patchlist
- core/include/config_pkg.sv: add COPRO_KECC_AES_K in copro_type_t
- core/include/build_config_pkg.sv enable 3 read ports
- core/include/cv64a6_imafdc_sv39_config_pkg.sv, core/include/cv64a6_imac_crypto_config_pkg.sv: set coprocessor type as COPRO_KECC_AES_K
- core/Flist.cva6: add kecc_aes_k_xif coprocessor files
- corev_apu/src/ariane.sv: instantiate coprocessor
- core/decoder.sv: redirect the 7 native AES64 (aes64es/esm/ds/dsm/ks2/im/ks1i) decode arms to
  the CV-X-IF illegal-instruction offload path instead of the native `AES` functional unit
  (`core/aes.sv`), whenever `CoproType == COPRO_KECC_AES_K`. AES64 keeps the real ratified
  Zknd/Zkne opcode encoding -- only the dispatch target changes.

## Instructions
- `xor3`, `xandn`, `rxri.l`, `rxri.h` (custom-1/2/3 opcode space, R4-type) -- see root README.
- `aes64es`, `aes64esm`, `aes64ds`, `aes64dsm`, `aes64ks2`, `aes64im`, `aes64ks1i` (real Zknd/Zkne
  opcode encoding, ported from aes-ext/cva6/core/crypto). AES32 is out of scope (RV32-only; every
  target in this repo is RV64). SHA/SM3/SM4/PACK/etc. from aes-ext are out of scope.

## Considered and not implemented
- **GHASH block-multiply** (`ghash_clmull`/`ghash_clmulh`, CUSTOM-0 opcode): prototyped as a
  dedicated 64x64->128 carry-less-multiply instruction pair, measured against the RISC-V
  B-extension's native `clmul`/`clmulh` (already present and enabled in this repo's target
  config, `core/multiplier.sv`) -- identical instruction count, no measurable cycle advantage
  (see `tests/result.md`'s "Results -- GHASH block-multiply"). Removed: it added RTL/opcode-table
  complexity for no benefit over what the base ISA already provides for free. GHASH acceleration
  in `tests/tightly/aes_gcm` now comes from native `clmul`/`clmulh`, not this coprocessor.
