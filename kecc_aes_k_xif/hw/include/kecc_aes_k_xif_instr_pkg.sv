// Keccak + AES64 Accelerator IP - Tightly
// Package for XIF custom instructions definition
// Author: Federico Runco
// AES64 instructions ported from aes-ext/cva6/core/crypto (Behnam Farnaghinejad)

package kecc_aes_k_xif_instr_pkg;

	// Allowed opcodes in the accellerator
	typedef enum logic [3:0] {
		ILLEGAL	= 4'b0000,
		XOR3 	= 4'b0001,
		XANDN 	= 4'b0010,
		RXRIL	= 4'b0011,
		RXRIH	= 4'b0100,
		AES64_1	= 4'b0101, // aes64es/aes64esm/aes64ds/aes64dsm/aes64ks2 (rs1, rs2)
		AES64_2	= 4'b0110  // aes64im/aes64ks1i (rs1 only)
	} opcode_t;

	// AES64 sub-operation, decoded from the instruction bits in the ex stage
	typedef enum {
		aes64_ds,
		aes64_dsm,
		aes64_es,
		aes64_esm,
		aes64_ks2,
		aes64_im,
		aes64_ks1i
	} aes64_t;

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

	// REF on custom opcodes: https://docs.riscv.org/reference/isa/_attachments/riscv-unprivileged.pdf chapter 35
	// R-type: funct7_rs2_rs1_funct3_rd_opcode
	// R4-type: rs3_funct2_rs2_rs1_funct3_rd_opcode
	// AES64 instructions keep the real RISC-V Zknd/Zkne opcode encoding (ratified K-extension),
	// redirected here from the native decoder.sv AES path -- see core/decoder.sv COPRO_KECC_AES_K handling.
	parameter int unsigned NbInstr = 6;
	parameter copro_issue_resp_t CoproInstr[NbInstr] = '{
		'{
			instr: 	32'b00000_10_00000_00000_000_00000_0101011, // CUSTOM-1 opcode, R4 type
			mask: 	32'b00000_11_00000_00000_111_00000_1111111,
			resp: 	'{accept: 1'b1, writeback: 1'b1, register_read: 3'b111},
			opcode:	XOR3
		},
		'{
			instr: 	32'b00000_10_00000_00000_001_00000_0101011, // CUSTOM-1 opcode, R4 type
			mask: 	32'b00000_11_00000_00000_111_00000_1111111,
			resp: 	'{accept: 1'b1, writeback: 1'b1, register_read: 3'b111},
			opcode:	XANDN
		},
		'{
			instr: 	32'b00000_00_00000_00000_000_00000_1011011, // CUSTOM-2 opcode, R4 type
			mask: 	32'b00000_00_00000_00000_000_00000_1111111,
			resp: 	'{accept: 1'b1, writeback: 1'b1, register_read: 3'b111},
			opcode:	RXRIL
		},
		'{
			instr: 	32'b00000_00_00000_00000_000_00000_1111011, // CUSTOM-3 opcode, R4 type
			mask: 	32'b00000_00_00000_00000_000_00000_1111111,
			resp: 	'{accept: 1'b1, writeback: 1'b1, register_read: 3'b111},
			opcode:	RXRIH
		},
		'{
			instr: 	32'b00110_01_00000_00000_0_00_00000_0110011, // aes64es/esm/ds/dsm/ks2 (Zknd/Zkne OP opcode)
			mask: 	32'b10110_01_00000_00000_1_11_00000_1111111,
			resp: 	'{accept: 1'b1, writeback: 1'b1, register_read: 3'b011}, // rs1, rs2
			opcode:	AES64_1
		},
		'{
			instr: 	32'b00110_00_00000_00000_0_01_00000_0010011, // aes64im/aes64ks1i (Zknd/Zkne OP-IMM opcode)
			mask: 	32'b11111_11_00000_00000_1_11_00000_1111111,
			resp: 	'{accept: 1'b1, writeback: 1'b1, register_read: 3'b001}, // rs1 only
			opcode:	AES64_2
		}
	};

endpackage