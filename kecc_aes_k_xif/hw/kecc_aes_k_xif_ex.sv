// Keccak + AES64 Accelerator IP - Tightly
// Module description for XIF execution logic
// Author: Federico Runco
// AES64 execution path ported from aes-ext/cva6/core/crypto/crypto_scalar_fu.sv (Behnam Farnaghinejad)

module kecc_aes_k_xif_ex
	import kecc_aes_k_xif_instr_pkg::*;
#(
	parameter int unsigned NrRgprPorts = 2,
	parameter int unsigned XLEN = 64,
	parameter type hartid_t = logic,
	parameter type id_t = logic,
	parameter type registers_t = logic,
	parameter type x_issue_req_t = logic
) (
	input	logic				clk_i,
	input	logic				rst_ni,
	input	registers_t			registers_i,
	input	opcode_t			opcode_i,
	input	hartid_t			hartid_i,
	input	id_t				id_i,
	input	logic [4:0]			rd_i,
	input	x_issue_req_t 		issue_req_i,
	output	logic [XLEN-1:0]	result_o,
	output	hartid_t			hartid_o,
	output	id_t				id_o,
	output	logic [4:0]			rd_o,
	output	logic				valid_o,
	output	logic				we_o
);
	logic [XLEN-1:0]	result_n;
	hartid_t 			hartid_n;
	id_t 				id_n;
	logic [4:0] 		rd_n;
	logic 				valid_n;
	logic 				we_n;

	// No combinatorial path is allowed between XIF inputs and outputs
	always_ff @(posedge clk_i, negedge rst_ni) begin
		if (~rst_ni) begin
			result_o	<= '0;
			hartid_o	<= '0;
			id_o		<= '0;
			rd_o		<= '0;
			valid_o		<= '0;
			we_o		<= '0;
		end else begin
			result_o	<= result_n;
			hartid_o	<= hartid_n;
			id_o		<= id_n;
			rd_o		<= rd_n;
			valid_o		<= valid_n;
			we_o		<= we_n;
		end
	end

	// AES64 sub-operation decode, mirroring aes-ext's crypto_scalar_fu.sv
	aes64_t	aes64_op;
	logic	aes64_en;
	always_comb begin
		aes64_en = 1'b0;
		aes64_op = aes64_t'(0);

		if (opcode_i == kecc_aes_k_xif_instr_pkg::AES64_1) begin
			aes64_en = 1'b1;
			if (issue_req_i.instr[30]) begin
				aes64_op = aes64_ks2;
			end else begin
				case (issue_req_i.instr[27:26])
					2'b00: aes64_op = aes64_es;
					2'b01: aes64_op = aes64_esm;
					2'b10: aes64_op = aes64_ds;
					2'b11: aes64_op = aes64_dsm;
				endcase
			end
		end else if (opcode_i == kecc_aes_k_xif_instr_pkg::AES64_2) begin
			aes64_en = 1'b1;
			aes64_op = issue_req_i.instr[24] ? aes64_ks1i : aes64_im;
		end
	end

	logic [XLEN-1:0] aes64_result;
	crypto_aes64 #(
		.XLEN (XLEN)
	) i_aes64 (
		.aes64_en_i		(aes64_en),
		.aes64_op_i		(aes64_op),
		.aes64_rs1_i	(registers_i[0]),
		.aes64_rs2_i	(registers_i[1]),
		.aes64_rnum_i	(issue_req_i.instr[23:20]),
		.aes64_result_o	(aes64_result)
	);

	// Execution logic for the different XIF instructions
	always_comb begin
		case (opcode_i)
			kecc_aes_k_xif_instr_pkg::XOR3: begin
				result_n	= registers_i[0] ^ registers_i[1] ^ registers_i[2];
				hartid_n	= hartid_i;
				id_n		= id_i;
				rd_n		= rd_i;
				valid_n		= 1'b1;
				we_n		= 1'b1;
			end
			kecc_aes_k_xif_instr_pkg::XANDN: begin
				result_n	= registers_i[0] ^ (~registers_i[1] & registers_i[2]);
				hartid_n	= hartid_i;
				id_n		= id_i;
				rd_n		= rd_i;
				valid_n		= 1'b1;
				we_n		= 1'b1;
			end
			kecc_aes_k_xif_instr_pkg::RXRIL, kecc_aes_k_xif_instr_pkg::RXRIH: begin
				int funct_imm;
				funct_imm = {issue_req_i.instr[26:25], issue_req_i.instr[14:12]};

				if (opcode_i == kecc_aes_k_xif_instr_pkg::RXRIH)
					funct_imm = funct_imm + 32;

				result_n	= rol(registers_i[0] ^ (registers_i[1] ^ {registers_i[2][XLEN-2:0], registers_i[2][XLEN-1]}), funct_imm);
				hartid_n    = hartid_i;
				id_n        = id_i;
				rd_n        = rd_i;
				valid_n     = 1'b1;
				we_n        = 1'b1;
			end
			kecc_aes_k_xif_instr_pkg::AES64_1, kecc_aes_k_xif_instr_pkg::AES64_2: begin
				result_n	= aes64_result;
				hartid_n	= hartid_i;
				id_n		= id_i;
				rd_n		= rd_i;
				valid_n		= 1'b1;
				we_n		= 1'b1;
			end
			default: begin
				result_n	= '0;
				hartid_n	= '0;
				id_n		= '0;
				rd_n		= '0;
				valid_n		= '0;
				we_n		= '0;
			end
		endcase
	end

	function automatic logic [XLEN-1:0] rol;
		input logic [XLEN-1:0] value;
		input int unsigned shamt;

		rol = (value << shamt) | (value >> (XLEN - shamt));
	endfunction
endmodule