# HASH IP — Keccak + SPHINCS+ Coprocessor for CVA6 (RV64)

A 64-bit native CV-X-IF coprocessor combining the [HORCRUX](../../crheepto_total)
Keccak-f permutation core, the SPHINCS+ THASH/PRF unified pipeline and the
WOTS+ chain-lengths accelerator. Replaces the previous `keccak_ip` 4-op narrow
ALU (xor3 / xandn / rotxor) with a self-contained hashing engine driven by 19
custom instructions.

---

## ✨ Features

| Capability                | Notes                                                  |
|---------------------------|--------------------------------------------------------|
| Keccak-f[1600]            | Full HORCRUX permutation core, reused verbatim         |
| 25×64-bit register file   | One Keccak lane per LOAD/STORE/KABSORB                 |
| SPHINCS+ THASH1/2 + PRF   | Robust + simple modes, security levels 128/192/256     |
| WOTS+ chain lengths       | base_w + checksum in HW for 128f/192f/256f             |
| CV-X-IF compliant         | Drop-in for CVA6 cvxif (NrRgprPorts=3, XLEN=64)        |

---

## 🧱 Module map

```
hash_ip/hw/
├── include/hash_pkg.sv        # opcode enum + CoproInstr table
├── keccak/                    # HORCRUX Keccak-f core (verbatim)
├── hash_register.sv           # 25×64-bit register file w/ XOR + bulk wb
├── chain_lengths.sv           # WOTS+ base_w + checksum
├── sphincs_ops.sv             # THASH/PRF FSM (re-uses Keccak)
├── hash.sv                    # Top compute (mux/wb/result)
├── hash_xif_id.sv             # CV-X-IF instruction decoder
├── hash_xif_ex.sv             # CV-X-IF execute (FSM + result registration)
├── hash_xif_cid.sv            # Compressed-instr predecode (passthrough)
└── hash_xif.sv                # CV-X-IF top wrapper
```

---

## 🧮 Instruction set (19 ops, all on `OpcodeCustom2 = 0x5B`)

R-type encoding `funct7 | rs2 | rs1 | funct3 | rd | 0x5B`. Decoded by `{funct3, funct7}`.

### Group 0 — Keccak control (`funct3 = 000`)
| funct7 | mnemonic   | semantics                                                  |
|--------|------------|------------------------------------------------------------|
| 0x00   | `OP_INIT`  | zero all 25 lanes                                          |
| 0x01   | `OP_KSTART`| start Keccak permutation (no register writeback)           |
| 0x02   | `OP_KPERM` | start Keccak permutation, write Dout back into the lanes   |

### Group 1 — Data IN (`funct3 = 001`, `rs1=data64`, `rs2=lane_idx`)
| funct7 | mnemonic     | semantics                                              |
|--------|--------------|--------------------------------------------------------|
| 0x00   | `OP_LOAD`    | `lane[rs2] <= rs1`                                     |
| 0x01   | `OP_KABSORB` | `lane[rs2] <= lane[rs2] ^ rs1`                         |

### Group 2 — Data OUT (`funct3 = 010`, `rd <= …`)
| funct7 | mnemonic     | semantics                                                            |
|--------|--------------|----------------------------------------------------------------------|
| 0x00   | `OP_STORE`   | `rd <= lane[rs1]` (or packed chain-length pair if WOTS+ active)      |
| 0x01   | `OP_KREAD3`  | `rd <= zext24(bytes[rs1+0..2])` for the byte-addressed lane array    |

### Group 3 — SPHINCS+ THASH/PRF (`funct3 = 011`, `rs2 = simple_mode`)
| funct7 | mnemonic           | sec | op            |
|--------|--------------------|-----|---------------|
| 0x00   | `OP_THASH1`        | 128 | THASH1        |
| 0x01   | `OP_THASH2`        | 128 | THASH2        |
| 0x02   | `OP_PRF_ADDR`      | 128 | PRF           |
| 0x03   | `OP_THASH1_192`    | 192 | THASH1        |
| 0x04   | `OP_THASH2_192`    | 192 | THASH2        |
| 0x05   | `OP_THASH1_256`    | 256 | THASH1        |
| 0x06   | `OP_THASH2_256`    | 256 | THASH2        |
| 0x07   | `OP_PRF_192`       | 192 | PRF           |
| 0x08   | `OP_PRF_256`       | 256 | PRF           |

### Group 4 — WOTS+ chain lengths (`funct3 = 100`, no operands)
| funct7 | mnemonic     | params              |
|--------|--------------|---------------------|
| 0x00   | `OP_CL_128F` | n=16, len1=32, len=67  |
| 0x01   | `OP_CL_192F` | n=24, len1=48, len=99  |
| 0x02   | `OP_CL_256F` | n=32, len1=64, len=131 |

After a `OP_CL_*` trigger the result lives in the chain_lengths internal regs;
subsequent `OP_STORE rd, idx` reads them out two 32-bit slots at a time
(packed into a single 64-bit `rd`).

---

## 🔌 CVA6 wiring

The coprocessor is selected by `CVA6Cfg.CoproType = COPRO_HASH`. Two configs
ship with HASH enabled by default:

- `core/include/cv64a6_imafdc_sv39_config_pkg.sv`
- `core/include/cv64a6_imac_crypto_config_pkg.sv`

`corev_apu/src/ariane.sv` instantiates `hash_xif` from the
`gen_COPRO_HASH` branch. The legacy `keccak_xif` IP is kept as
`COPRO_KECCAK` for backwards compatibility.

Filelists are updated in:

- `core/Flist.cva6`
- `core/Flist.cva6_gate`
- `Flist.ariane`

---

## 🧠 Execution timing

| op class           | latency (cycles, issue → result_valid) |
|--------------------|----------------------------------------|
| INIT/LOAD/KABSORB  | 1                                       |
| STORE/KREAD3/CL_*  | 1                                       |
| KSTART/KPERM       | 1 + 25 (Keccak-f rounds)                |
| THASH simple, PRF  | 1 + 26 (one Keccak-f)                   |
| THASH robust       | 1 + 52 (two Keccak-f)                   |

`hash_xif` deasserts `issue_ready` while a multi-cycle op is in flight, so
software can issue back-to-back instructions without manual stalls.

---

## 📝 Status

RTL + filelist integration complete. SW test ports under `tests/` and
simulation harnesses are TBD.
