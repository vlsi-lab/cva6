// Copyright 2025 PoliTO - EDGE Group, @VLSI Lab
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
//
// HASH coprocessor package - 64-bit native register file (CVA6 RV64).
// Replaces the legacy keccak_xif IP with a Keccak/SPHINCS+ accelerator
// reusing the HORCRUX permutation core but exposing 64-bit data lanes
// (one full Keccak lane per LOAD/STORE/KABSORB/KREAD).
//
// 19 instructions:
//   Keccak primitives (7) : OP_INIT, OP_KSTART, OP_KPERM, OP_LOAD, OP_KABSORB,
//                            OP_STORE, OP_KREAD3
//   SPHINCS+ ops      (9) : OP_THASH1/2(_192/_256), OP_PRF_ADDR/_192/_256
//   WOTS+ chain lengths(3): OP_CL_128F, OP_CL_192F, OP_CL_256F
//
// All ops live on RISC-V CUSTOM-2 opcode (0x5B). Decoded via {funct3, funct7}.

package hash_pkg;

  // --------------------------------------------------------------------------
  // Opcode enum (internal control signal carried from ID -> EX)
  // --------------------------------------------------------------------------
  typedef enum logic [4:0] {
    OP_NONE         = 5'd0,
    OP_INIT         = 5'd1,
    OP_KSTART       = 5'd2,
    OP_KPERM        = 5'd3,
    OP_LOAD         = 5'd4,
    OP_KABSORB      = 5'd5,
    OP_STORE        = 5'd6,
    OP_KREAD3       = 5'd7,
    OP_THASH1       = 5'd8,
    OP_THASH2       = 5'd9,
    OP_PRF_ADDR     = 5'd10,
    OP_THASH1_192   = 5'd11,
    OP_THASH2_192   = 5'd12,
    OP_THASH1_256   = 5'd13,
    OP_THASH2_256   = 5'd14,
    OP_PRF_192      = 5'd15,
    OP_PRF_256      = 5'd16,
    OP_CL_128F      = 5'd17,
    OP_CL_192F      = 5'd18,
    OP_CL_256F      = 5'd19,
    OP_LOAD2        = 5'd20    // 128-bit dual-lane load (rs1=lo64, rs2=hi64, rs3=idx)
  } opcode_t;

  // --------------------------------------------------------------------------
  // CV-X-IF issue response typedefs (mirror keccak_xif_instr_pkg)
  // --------------------------------------------------------------------------
  typedef struct packed {
    logic       accept;
    logic       writeback;
    logic [2:0] register_read;     // {rs3, rs2, rs1}
  } issue_resp_t;

  typedef struct packed {
    logic [31:0] instr;
    logic [31:0] mask;
    issue_resp_t resp;
    opcode_t     opcode;
  } copro_issue_resp_t;

  // --------------------------------------------------------------------------
  // Encoding helpers (R-type on CUSTOM-2 opcode 0b1011011 = 0x5B)
  // mask covers funct7 [31:25] | funct3 [14:12] | opcode [6:0] => 32'hFE00_707F
  // --------------------------------------------------------------------------
  localparam logic [6:0]  HASH_OPCODE = 7'b1011011;     // RISC-V CUSTOM-2
  localparam logic [31:0] HASH_MASK   = 32'hFE00_707F;

  // helper expanded inline (Verilog parameter functions are limited; we just
  // keep the encoding columns explicit below for readability)

  parameter int unsigned NbInstr = 20;
  parameter copro_issue_resp_t CoproInstr[NbInstr] = '{
    // ---- Group 0: control ops, no register reads, no writeback ----
    '{ instr: {7'h00, 5'b0, 5'b0, 3'b000, 5'b0, HASH_OPCODE},
       mask : HASH_MASK,
       resp : '{accept:1'b1, writeback:1'b0, register_read:3'b000},
       opcode: OP_INIT },
    '{ instr: {7'h01, 5'b0, 5'b0, 3'b000, 5'b0, HASH_OPCODE},
       mask : HASH_MASK,
       resp : '{accept:1'b1, writeback:1'b0, register_read:3'b000},
       opcode: OP_KSTART },
    '{ instr: {7'h02, 5'b0, 5'b0, 3'b000, 5'b0, HASH_OPCODE},
       mask : HASH_MASK,
       resp : '{accept:1'b1, writeback:1'b0, register_read:3'b000},
       opcode: OP_KPERM },

    // ---- Group 1: data IN (rs1=data64, rs2=lane index), no writeback ----
    '{ instr: {7'h00, 5'b0, 5'b0, 3'b001, 5'b0, HASH_OPCODE},
       mask : HASH_MASK,
       resp : '{accept:1'b1, writeback:1'b0, register_read:3'b011},
       opcode: OP_LOAD },
    '{ instr: {7'h01, 5'b0, 5'b0, 3'b001, 5'b0, HASH_OPCODE},
       mask : HASH_MASK,
       resp : '{accept:1'b1, writeback:1'b0, register_read:3'b011},
       opcode: OP_KABSORB },

    // ---- Group 2: data OUT (rs1=index/byte_offset), writeback to rd ----
    '{ instr: {7'h00, 5'b0, 5'b0, 3'b010, 5'b0, HASH_OPCODE},
       mask : HASH_MASK,
       resp : '{accept:1'b1, writeback:1'b1, register_read:3'b001},
       opcode: OP_STORE },
    '{ instr: {7'h01, 5'b0, 5'b0, 3'b010, 5'b0, HASH_OPCODE},
       mask : HASH_MASK,
       resp : '{accept:1'b1, writeback:1'b1, register_read:3'b001},
       opcode: OP_KREAD3 },

    // ---- Group 3: SPHINCS+ thash / prf ; rs2 carries simple_mode flag ----
    '{ instr: {7'h00, 5'b0, 5'b0, 3'b011, 5'b0, HASH_OPCODE},
       mask : HASH_MASK,
       resp : '{accept:1'b1, writeback:1'b0, register_read:3'b010},
       opcode: OP_THASH1 },
    '{ instr: {7'h01, 5'b0, 5'b0, 3'b011, 5'b0, HASH_OPCODE},
       mask : HASH_MASK,
       resp : '{accept:1'b1, writeback:1'b0, register_read:3'b010},
       opcode: OP_THASH2 },
    '{ instr: {7'h02, 5'b0, 5'b0, 3'b011, 5'b0, HASH_OPCODE},
       mask : HASH_MASK,
       resp : '{accept:1'b1, writeback:1'b0, register_read:3'b000},
       opcode: OP_PRF_ADDR },
    '{ instr: {7'h03, 5'b0, 5'b0, 3'b011, 5'b0, HASH_OPCODE},
       mask : HASH_MASK,
       resp : '{accept:1'b1, writeback:1'b0, register_read:3'b010},
       opcode: OP_THASH1_192 },
    '{ instr: {7'h04, 5'b0, 5'b0, 3'b011, 5'b0, HASH_OPCODE},
       mask : HASH_MASK,
       resp : '{accept:1'b1, writeback:1'b0, register_read:3'b010},
       opcode: OP_THASH2_192 },
    '{ instr: {7'h05, 5'b0, 5'b0, 3'b011, 5'b0, HASH_OPCODE},
       mask : HASH_MASK,
       resp : '{accept:1'b1, writeback:1'b0, register_read:3'b010},
       opcode: OP_THASH1_256 },
    '{ instr: {7'h06, 5'b0, 5'b0, 3'b011, 5'b0, HASH_OPCODE},
       mask : HASH_MASK,
       resp : '{accept:1'b1, writeback:1'b0, register_read:3'b010},
       opcode: OP_THASH2_256 },
    '{ instr: {7'h07, 5'b0, 5'b0, 3'b011, 5'b0, HASH_OPCODE},
       mask : HASH_MASK,
       resp : '{accept:1'b1, writeback:1'b0, register_read:3'b000},
       opcode: OP_PRF_192 },
    '{ instr: {7'h08, 5'b0, 5'b0, 3'b011, 5'b0, HASH_OPCODE},
       mask : HASH_MASK,
       resp : '{accept:1'b1, writeback:1'b0, register_read:3'b000},
       opcode: OP_PRF_256 },

    // ---- Group 4: WOTS+ chain lengths (no operands, no writeback) ----
    '{ instr: {7'h00, 5'b0, 5'b0, 3'b100, 5'b0, HASH_OPCODE},
       mask : HASH_MASK,
       resp : '{accept:1'b1, writeback:1'b0, register_read:3'b000},
       opcode: OP_CL_128F },
    '{ instr: {7'h01, 5'b0, 5'b0, 3'b100, 5'b0, HASH_OPCODE},
       mask : HASH_MASK,
       resp : '{accept:1'b1, writeback:1'b0, register_read:3'b000},
       opcode: OP_CL_192F },
    '{ instr: {7'h02, 5'b0, 5'b0, 3'b100, 5'b0, HASH_OPCODE},
       mask : HASH_MASK,
       resp : '{accept:1'b1, writeback:1'b0, register_read:3'b000},
       opcode: OP_CL_256F },

    // ---- Group 5: 128-bit dual-lane LOAD (R4-type) ----
    //   rs1 = lo64 -> lane[rs3]
    //   rs2 = hi64 -> lane[rs3 + 1]
    //   funct3 = 3'b101 (unused by groups 0-4); funct2 = 0; rs3 = lane index
    //   Mask covers only funct3 + opcode so any rs3 value matches.
    '{ instr: {5'h00, 2'h0, 5'b0, 5'b0, 3'b101, 5'b0, HASH_OPCODE},
       mask : 32'h0000_707F,
       resp : '{accept:1'b1, writeback:1'b0, register_read:3'b111},
       opcode: OP_LOAD2 }
  };

  // --------------------------------------------------------------------------
  // Compressed-instruction predecode (none supported) - kept for symmetry
  // with keccak_xif_cid plumbing.
  // --------------------------------------------------------------------------
  typedef struct packed {
    logic        accept;
    logic [31:0] instr;
  } compressed_resp_t;

  typedef struct packed {
    logic [15:0]      instr;
    logic [15:0]      mask;
    compressed_resp_t resp;
  } copro_compressed_resp_t;

  parameter int unsigned NbCompInstr = 1;
  parameter copro_compressed_resp_t CoproCompInstr[NbCompInstr] = '{
    '{ instr: 16'h0000, mask: 16'hFFFF,
       resp : '{accept: 1'b0, instr: 32'h0000_0000} }
  };

endpackage
