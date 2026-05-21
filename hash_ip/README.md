# HASH IP — Keccak + SPHINCS+ Coprocessor for CVA6 (RV64)

A 64-bit native CV-X-IF coprocessor combining the [HORCRUX](../../crheepto_total)
Keccak-f permutation core, the SPHINCS+ THASH/PRF unified pipeline and the
WOTS+ chain-lengths accelerator. Replaces the previous `keccak_ip` 4-op narrow
ALU (xor3 / xandn / rotxor) with a self-contained hashing engine driven by 20
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

## 🔬 Hardware architecture (paper-ready)

This IP is a tightly-coupled coprocessor attached to CVA6 through CV-X-IF,
with a split decode/execute frontend and a shared cryptographic backend:

- Frontend:
	- `hash_xif_id.sv`: decodes `{funct3, funct7}` into internal opcodes and
		requests only the source registers needed by each instruction.
	- `hash_xif_ex.sv`: classifies ops into single-cycle vs multi-cycle,
		captures instruction context (`hartid/id/rd`), and emits registered
		CV-X-IF result responses.
	- `hash_xif.sv`: top CV-X-IF wrapper that stalls issue while a multi-cycle
		operation is in flight (`issue_ready = issue_ready_id & ~ex_busy`).

- Backend compute:
	- `hash_register.sv`: 25x64-bit state register file (one Keccak lane each),
		with both 64-bit and 50x32-bit views.
	- `keccak/keccak_f.sv`: shared Keccak-f[1600] permutation datapath.
	- `sphincs_ops.sv`: unified THASH1/THASH2/PRF micro-FSM for 128/192/256.
	- `chain_lengths.sv`: WOTS+ base_w + checksum datapath for 128f/192f/256f.

### Datapath organization

- Native state width: 1600 bits mapped as 25 lanes x 64 bits.
- Storage model:
	- Lane view: `lanes64[0..24]` for direct LOAD/STORE/KABSORB accesses.
	- Word view: `lanes32[0..49]` for SPHINCS+ and chain-length logic.
- Keccak input mux:
	- Normal mode: flattened register file state.
	- SPHINCS mode: FSM-constructed Keccak state (`sphincs_keccak_input`).
- Writeback arbitration:
	- A single bulk writeback path updates all 25 lanes either from Keccak
		output (KPERM path) or from SPHINCS packed 32-bit words.
	- Priority in register file is deterministic:
		`init > bulk_writeback > dual_write(OP_LOAD2) > single_write(OP_LOAD) > xor(OP_KABSORB)`.

### Control and execution model

- Single-cycle class (1 cycle issue-to-result):
	`INIT`, `LOAD`, `LOAD2`, `KABSORB`, `STORE`, `KREAD3`, `CL_*`.
- Multi-cycle class:
	`KSTART`, `KPERM`, `THASH*`, `PRF*`.
- Backpressure behavior:
	- During multi-cycle ops, `hash_xif` deasserts `issue_ready`, so CVA6
		naturally stalls further custom issues without software-inserted NOPs.
	- `result_valid` is pulsed only at completion and carries the latched
		transaction metadata.

### SPHINCS+ microarchitecture

`sphincs_ops.sv` implements a unified FSM with states:

`IDLE -> ABSORB_1 -> WAIT_1 -> [ABSORB_2 -> WAIT_2] -> STORE_RESULT`

- Operation mapping:
	- PRF and THASH simple: one Keccak permutation.
	- THASH robust: two Keccak permutations.
- Security-level parameterization:
	- 128f: `N=16 bytes`
	- 192f: `N=24 bytes`
	- 256f: `N=32 bytes`
- Robust THASH flow:
	- Pass 1 generates bitmask (`N` bytes for THASH1, `2N` for THASH2).
	- Input is XOR-masked in hardware.
	- Pass 2 hashes `(pub_seed || addr || masked_input || pad)`.
- Padding and absorb domain:
	- SHAKE256 rate portion is explicitly constructed (1088 bits), with
		`0x1F` domain-separation and terminal `0x80` byte in the rate lane.

### WOTS+ chain-length datapath

- Input extraction:
	- Reads message material from register words and expands into nibbles.
- Parallel arithmetic:
	- Computes checksum trees for 128f/192f/256f.
	- Performs left shift by 4 (LEN2=3 nibbles) and packs checksum nibbles.
- Output packing:
	- Produces up to 9 32-bit words (`result_regs[0..8]`).
	- `OP_STORE` returns two chain-length words packed in one 64-bit register
		while chain-length mode is active.

### State access primitives

- `OP_LOAD`: writes one 64-bit lane.
- `OP_LOAD2`: writes two consecutive 64-bit lanes in one issue
	(`rs1->lane[idx]`, `rs2->lane[idx+1]`), with saturated index on the
	top lane to avoid out-of-range writes.
- `OP_KABSORB`: in-place lane XOR.
- `OP_STORE`: returns one 64-bit lane or chain-length packed data.
- `OP_KREAD3`: returns zero-extended 24-bit slices from a byte-addressed
	window spanning one or two adjacent lanes.

This organization allows software to stream state words with low overhead,
while preserving a single shared Keccak core for all permutation-based
operations.

---

## 🧮 Instruction set (20 ops, all on `OpcodeCustom2 = 0x5B`)

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

### Group 5 — Dual-lane Data IN (`funct3 = 101`, R4-type)
| funct7[6:2] | mnemonic    | semantics                                                      |
|-------------|-------------|----------------------------------------------------------------|
| 0x00        | `OP_LOAD2`  | `lane[rs3] <= rs1`, `lane[min(rs3+1,24)] <= rs2`             |

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
| INIT/LOAD/LOAD2/KABSORB | 1                                  |
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
