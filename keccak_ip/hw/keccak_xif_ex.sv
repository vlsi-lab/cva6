// Keccak Accellerator IP - Tightly
// Module description for XIF execution logic 
// Author: Federico Runco

module keccak_xif_ex
	import keccak_xif_instr_pkg::*;
#(
	parameter int unsigned NrRgprPorts = 2,
	parameter int unsigned XLEN = 64,
	parameter type hartid_t = logic,
	parameter type id_t = logic,
	parameter type registers_t = logic
) (
	input	logic				clk_i,
	input	logic				rst_ni,
	input	registers_t			registers_i,
	input	opcode_t			opcode_i,
	input	hartid_t			hartid_i,
	input	id_t				id_i,
	input	logic [4:0]			rd_i,
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

	// Execution logic for the different XIF instructions
	always_comb begin
		case (opcode_i)
			keccak_xif_instr_pkg::XOR3: begin
				result_n	= registers_i[0] ^ registers_i[1] ^ registers_i[2];
				hartid_n	= hartid_i;
				id_n		= id_i;
				rd_n		= rd_i;
				valid_n		= 1'b1;
				we_n		= 1'b1;
			end
			keccak_xif_instr_pkg::KTOP: begin
				result_n	= registers_i[0] ^ {registers_i[1][XLEN-2:0], registers_i[1][XLEN-1]};
				hartid_n	= hartid_i;
				id_n		= id_i;
				rd_n		= rd_i;
				valid_n		= 1'b1;
				we_n		= 1'b1;
			end
			keccak_xif_instr_pkg::KCOP: begin
				result_n	= registers_i[0] ^ (~registers_i[1] & registers_i[2]);
				hartid_n	= hartid_i;
				id_n		= id_i;
				rd_n		= rd_i;
				valid_n		= 1'b1;
				we_n		= 1'b1;
			end
			keccak_xif_instr_pkg::DXROLS: begin
				result_n	= registers_i[0] ^ (registers_i[1] ^ {registers_i[2][XLEN-2:0], registers_i[2][XLEN-1]});
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

endmodule