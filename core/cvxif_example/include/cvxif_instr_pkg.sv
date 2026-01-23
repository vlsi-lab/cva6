// Copyright 2021 Thales DIS design services SAS
//
// Licensed under the Solderpad Hardware Licence, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.0
// You may obtain a copy of the License at https://solderpad.org/licenses/
//
// Original Author: Guillaume Chauvon (guillaume.chauvon@thalesgroup.com)



package cvxif_instr_pkg;

  typedef enum logic [3:0] {
    ILLEGAL         = 4'b0000,
    NOP             = 4'b0001,
    MONTG_KYBER     = 4'b0010,
    MONTG_FALCON    = 4'b0011,
    MONTG_NEWHOPE   = 4'b0100,
    MONTG_NTRU      = 4'b0101,
    MONTG_DILITHIUM = 4'b0110,
    BARRETT         = 4'b0111,
    GF_MUL          = 4'b1000,
    KARATS_1        = 4'b1001,
    KARATS_2        = 4'b1010
  } opcode_t;


  typedef struct packed {
    logic accept;
    logic writeback;  // TODO depends on dualwrite
    logic [2:0] register_read;  // TODO Nr read ports
  } issue_resp_t;

  typedef struct packed {
    logic        accept;
    logic [31:0] instr;
  } compressed_resp_t;

  typedef struct packed {
    logic [31:0] instr;
    logic [31:0] mask;
    issue_resp_t resp;
    opcode_t     opcode;
  } copro_issue_resp_t;


  //typedef struct packed {
  //  logic [15:0]      instr;
  //  logic [15:0]      mask;
  //  compressed_resp_t resp;
  //} copro_compressed_resp_t;

  // 4 Possible RISCV instructions for Coprocessor
  parameter int unsigned NbInstr = 10;

  parameter copro_issue_resp_t CoproInstr[NbInstr] = '{
      '{
          // Custom Nop
          instr:
          32'b00000_00_00000_00000_0_00_00000_1111011,  // custom3 opcode
          mask: 32'b11111_11_00000_00000_1_11_00000_1111111,
          resp : '{accept : 1'b1, writeback : 1'b0, register_read : {1'b0, 1'b0, 1'b0}},
          opcode : NOP
      },
      '{
          // Custom MONTG_KYBER : MONTG_KYBER rd, rs1, rs2
          instr:
          32'b00000_00_00000_00000_0_01_00000_1111011,  // custom3 opcode
          mask: 32'b11111_11_00000_00000_1_11_00000_1111111,
          resp : '{accept : 1'b1, writeback : 1'b1, register_read : {1'b0, 1'b1, 1'b1}},
          opcode : MONTG_KYBER
      },
      '{
          // Custom MONTG_FALCON : MONTG_FALCON rd, rs1, rs1
          instr:
          32'b00000_01_00000_00000_0_01_00000_1111011,  // custom3 opcode
          mask: 32'b11111_11_00000_00000_1_11_00000_1111111,
          resp : '{accept : 1'b1, writeback : 1'b1, register_read : {1'b0, 1'b0, 1'b1}},
          opcode : MONTG_FALCON
      },
      '{
          // Custom MONTG_NEWHOPE : MONTG_NEWHOPE rd, rs2, rs2
          instr:
          32'b00000_10_00000_00000_0_01_00000_1111011,  // custom3 opcode
          mask: 32'b11111_11_00000_00000_1_11_00000_1111111,
          resp : '{accept : 1'b1, writeback : 1'b1, register_read : {1'b0, 1'b1, 1'b0}},
          opcode : MONTG_NEWHOPE
      },
      '{
          // Custom MONTG_NTRU : MONTG_NTRU rd, rs1, rs1
          instr:
          32'b00000_11_00000_00000_0_01_00000_1111011,  // custom3 opcode
          mask: 32'b11111_11_00000_00000_1_11_00000_1111111,
          resp : '{accept : 1'b1, writeback : 1'b1, register_read : {1'b0, 1'b1, 1'b1}},
          opcode : MONTG_NTRU
      },
      '{
          // Custom MONTG_DILITHIUM : MONTG_DILITHIUM rd, rs1, rs1
          instr:
          32'b00001_00_00000_00000_0_01_00000_1111011,  // custom3 opcode
          mask: 32'b11111_11_00000_00000_1_11_00000_1111111,
          resp : '{accept : 1'b1, writeback : 1'b1, register_read : {1'b1, 1'b1, 1'b1}},
          opcode : MONTG_DILITHIUM
      },
      '{
          // Custom BARRETT : BARRETT rd, rs1, rs2
          instr:
          32'b00001_01_00000_00000_0_01_00000_1111011,  // custom3 opcode
          mask: 32'b11111_11_00000_00000_1_11_00000_1111111,
          resp : '{accept : 1'b1, writeback : 1'b1, register_read : {1'b1, 1'b1, 1'b1}},
          opcode : BARRETT
      },
      '{
            // Custom GF_MUL : GF_MUL rd, rs1, rs2
            instr:
            32'b00001_10_00000_00000_0_01_00000_1111011,  // custom3 opcode
            mask: 32'b11111_11_00000_00000_1_11_00000_1111111,
            resp : '{accept : 1'b1, writeback : 1'b1, register_read : {1'b1, 1'b1, 1'b1}},
            opcode : GF_MUL
        },
        '{
            // Custom KARATS_1 : KARATS_1 rd, rs1, rs2
            instr:
            32'b00001_11_00000_00000_0_01_00000_1111011,  // custom3 opcode
            mask: 32'b11111_11_00000_00000_1_11_00000_1111111,
            resp : '{accept : 1'b1, writeback : 1'b1, register_read : {1'b1, 1'b1, 1'b1}},
            opcode : KARATS_1
        },
        '{
            // Custom KARATS_2 : KARATS_2 rd, rs1, rs2
            instr:
            32'b00010_00_00000_00000_0_01_00000_1111011,  // custom3 opcode
            mask: 32'b11111_11_00000_00000_1_11_00000_1111111,
            resp : '{accept : 1'b1, writeback : 1'b1, register_read : {1'b1, 1'b1, 1'b1}},
            opcode : KARATS_2
        }

  };



  //parameter int unsigned NbCompInstr = 2;
  //parameter copro_compressed_resp_t CoproCompInstr[NbCompInstr] = '{
  //    // C_NOP
  //    '{
  //        instr : 16'b111_0_00000_00000_00,
  //        mask : 16'b111_1_00000_00000_11,
  //        resp : '{accept : 1'b1, instr : 32'b00000_00_00000_00000_0_00_00000_1111011}
  //    },
  //    '{
  //        instr : 16'b111_1_00000_00000_00,
  //        mask : 16'b111_1_00000_00000_11,
  //        resp : '{accept : 1'b1, instr : 32'b00000_00_00000_00000_0_01_01010_1111011}
  //    }
  //};

endpackage
