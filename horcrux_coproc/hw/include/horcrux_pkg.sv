//////////////////////////////////////////////////////////////////////////////////////////
// Engineer:      Alessandra Dolmeta - alessandra.dolmeta@polito.it                     //
//                Valeria Piscopo    - valeria.piscopo@polito.it                        //
//                                                                                      //
//////////////////////////////////////////////////////////////////////////////////////////

package horcrux_pkg;

	// Allowed opcodes in the accellerator
	typedef enum logic [6:0] {
		ILLEGAL	        = 7'b0000000,
		XOR3 	        = 7'b0000001,
		XANDN 	        = 7'b0000010,
		RXRIL	        = 7'b0000011,
		RXRIH	        = 7'b0000100,
		MONTG_KYBER     = 7'b0000101,
		MONTG_NEWHOPE   = 7'b0000110,
		MONTG_FALCON    = 7'b0000111,
		MONTG_NTRU      = 7'b0001000,
		MONTG_DILITHIUM = 7'b0001001
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

	// REF on custom opcodes: https://docs.riscv.org/reference/isa/_attachments/riscv-unprivileged.pdf chapter 35
	// R-type: funct7_rs2_rs1_funct3_rd_opcode
	// R4-type: rs3_funct2_rs2_rs1_funct3_rd_opcode
	parameter int unsigned NbInstr = 9;

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
			instr: 32'b0000000_00000_00000_111_00000_1111011,  // MONTG KYBER, 3b, 0x07, 0x00
			mask:  32'b1111111_00000_00000_111_00000_1111111,
			resp:  '{accept: 1'b1, writeback: 1'b1, register_read: 3'b100},
			opcode: MONTG_KYBER
		}, 
		'{ 
			instr: 32'b0000001_00000_00000_111_00000_1111011,  // MONTG NEWHOPE
			mask:  32'b1111111_00000_00000_111_00000_1111111,
			resp:  '{accept: 1'b1, writeback: 1'b1, register_read: 3'b100},
			opcode: MONTG_NEWHOPE
		},
		'{ 
			instr: 32'b0000010_00000_00000_111_00000_1111011,  // MONTG FALCON
			mask:  32'b1111111_00000_00000_111_00000_1111111,
			resp:  '{accept: 1'b1, writeback: 1'b1, register_read: 3'b100},
			opcode: MONTG_FALCON
		},
		'{ 
			instr: 32'b0000011_00000_00000_111_00000_1111011,  // MONTG NTRU
			mask:  32'b1111111_00000_00000_111_00000_1111111,
			resp:  '{accept: 1'b1, writeback: 1'b1, register_read: 3'b100},
			opcode: MONTG_NTRU
		},
		'{ 
			instr: 32'b0000100_00000_00000_111_00000_1111011,  // MONTG DILITHIUM
			mask:  32'b1111111_00000_00000_111_00000_1111111,
			resp:  '{accept: 1'b1, writeback: 1'b1, register_read: 3'b100},
			opcode: MONTG_DILITHIUM
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