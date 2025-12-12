// Keccak Accellerator IP - Tightly
// Package for XIF custom instructions definition
// Author: Federico Runco

package keccak_xif_instr_pkg;

	// Allowed opcodes in the accellerator
	typedef enum logic [3:0] {
		ILLEGAL	= 4'b0000,
		XOR3 	= 4'b0001,
		XANDN 	= 4'b0010,
		DXROLS 	= 4'b0011
	} opcode_t;

	// CV-X-IF issue response typedefs
	typedef struct packed {
		logic 		accept;
		logic 		writeback; 
		logic [2:0]	register_read; 
	} issue_resp_t;

	typedef struct packed {
		logic [31:0] instr;
		logic [31:0] mask;
		issue_resp_t resp;
		opcode_t     opcode;
	} copro_issue_resp_t;

	// Instruction encoding (madd, unsupported extension of fpu to offload instr)
	// REF on custom opcodes: https://docs.riscv.org/reference/isa/_attachments/riscv-unprivileged.pdf chapter 35
	// R-type: funct7_rs2_rs1_funct3_rd_opcode
	// R4-type: rs3_funct2_rs2_rs1_funct3_rd_opcode
	parameter int unsigned NbInstr = 3;
	parameter copro_issue_resp_t CoproInstr[NbInstr] = '{
		'{
			instr: 	32'b00000_10_00000_00000_000_00000_1000011, // MADD opcode, R4 type
			mask: 	32'b00000_11_00000_00000_111_00000_1111111,
			resp: 	'{accept: 1'b1, writeback: 1'b1, register_read: 3'b111},
			opcode:	XOR3
		},
		'{
			instr: 	32'b00000_10_00000_00000_001_00000_1000011, // MADD opcode, R4 type
			mask: 	32'b00000_11_00000_00000_111_00000_1111111,
			resp: 	'{accept: 1'b1, writeback: 1'b1, register_read: 3'b111},
			opcode:	XANDN
		},
		'{
			instr: 	32'b00000_10_00000_00000_010_00000_1000011, // MADD opcode, R4 type
			mask: 	32'b00000_11_00000_00000_111_00000_1111111,
			resp: 	'{accept: 1'b1, writeback: 1'b1, register_read: 3'b111},
			opcode:	DXROLS
		}
	};

	// TODO: compressed instructions are not supported on CVA6 XIF, still need to implement?
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
		'{instr: 16'h0000, mask: 16'hFFFF, resp:'{accept: 1'b0, instr: 32'h00000000 }}
	};

endpackage