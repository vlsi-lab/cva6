// Keccak Accelerator IP - Tightly
// Top module description for XIF execution unit 
// Author: Federico Runco

module keccak_xif 
	import keccak_xif_instr_pkg::*;
#(
	parameter	int unsigned	NrRgprPorts			= 2,
	parameter	int unsigned	XLEN				= 64,
	parameter	type 			readregflags_t		= logic,
	parameter	type 			writeregflags_t		= logic,
	parameter	type 			id_t				= logic,
	parameter	type 			hartid_t			= logic,
	parameter	type 			x_compressed_req_t 	= logic,
	parameter	type 			x_compressed_resp_t	= logic,
	parameter	type 			x_issue_req_t		= logic,
	parameter	type 			x_issue_resp_t		= logic,
	parameter	type 			x_register_t		= logic,
	parameter	type 			x_commit_t			= logic,
	parameter	type 			x_result_t			= logic,
	parameter	type 			cvxif_req_t			= logic,
	parameter	type 			cvxif_resp_t		= logic,
	localparam 	type 			registers_t			= logic [NrRgprPorts-1:0][XLEN-1:0]
) (
	input	logic			clk_i,
	input	logic			rst_ni,
	input	cvxif_req_t		cvxif_req_i,
	output	cvxif_resp_t	cvxif_resp_o
);
	// Issue interface signals
	x_issue_req_t		issue_req;
	x_issue_resp_t		issue_resp;
	logic				issue_valid, issue_ready;

	// Registers interface signals
	x_register_t	register;
	logic			register_valid;	

	// Execution unit signals
	registers_t			registers;
	opcode_t			opcode;
	hartid_t			issue_hartid, hartid;
	id_t				issue_id, id;
	logic [4:0]			issue_rd, rd;
	logic [XLEN-1:0]	result;
	logic				we;

	logic ex_valid;

	// XIF issue unpacking TODO: use directly cvxif signals
	assign issue_req		= cvxif_req_i.issue_req;
	assign issue_valid		= cvxif_req_i.issue_valid;
	assign register			= cvxif_req_i.register;
	assign register_valid	= cvxif_req_i.register_valid;

	// Units instantiation
	keccak_xif_id #(
		.copro_issue_resp_t (keccak_xif_instr_pkg::copro_issue_resp_t),
		.opcode_t			(keccak_xif_instr_pkg::opcode_t),
		.NbInstr			(keccak_xif_instr_pkg::NbInstr),
		.CoproInstr			(keccak_xif_instr_pkg::CoproInstr),
		.NrRgprPorts		(NrRgprPorts),
		.hartid_t			(hartid_t),
		.id_t				(id_t),
		.x_issue_req_t		(x_issue_req_t),
		.x_issue_resp_t		(x_issue_resp_t),
		.x_register_t		(x_register_t),
		.registers_t		(registers_t)
	) i_id (
		.clk_i				(clk_i),
		.rst_ni				(rst_ni),
		.issue_valid_i		(issue_valid),
		.issue_req_i		(issue_req),
		.issue_ready_o		(issue_ready),
		.issue_resp_o		(issue_resp),
		.register_valid_i	(register_valid),
		.register_i			(register),
		.registers_o		(registers),
		.opcode_o			(opcode),
		.hartid_o			(issue_hartid),
		.id_o				(issue_id),
		.rd_o				(issue_rd)
	);

	keccak_xif_ex #(
		.NrRgprPorts	(NrRgprPorts),
		.XLEN			(XLEN),
		.hartid_t		(hartid_t),
		.id_t			(id_t),
		.registers_t	(registers_t),
		.x_issue_req_t	(x_issue_req_t)
	) i_ex (
		.clk_i			(clk_i),
      	.rst_ni			(rst_ni),
    	.registers_i	(registers),
    	.opcode_i		(opcode),
    	.hartid_i		(issue_hartid),
    	.id_i			(issue_id),
    	.rd_i			(issue_rd),
		.issue_req_i	(issue_req),
    	.hartid_o		(hartid),
    	.id_o			(id),
    	.result_o		(result),
    	.valid_o		(ex_valid),
    	.rd_o			(rd),
    	.we_o			(we)
	);

	// Output response 
	always_comb begin
		cvxif_resp_o.result_valid = ex_valid;
		cvxif_resp_o.result.hartid = hartid;
		cvxif_resp_o.result.id = id;
		cvxif_resp_o.result.data = result;
		cvxif_resp_o.result.rd = rd;
		cvxif_resp_o.result.we = we;
		cvxif_resp_o.issue_ready = issue_ready;
		cvxif_resp_o.issue_resp = issue_resp;
		cvxif_resp_o.register_ready = cvxif_resp_o.issue_ready;
	end

	// TODO: delete compressed
	x_compressed_req_t		compressed_req;
	x_compressed_resp_t 	compressed_resp;
	logic					compressed_valid, compressed_ready;

	assign compressed_req 	= cvxif_req_i.compressed_req;
	assign compressed_valid	= cvxif_req_i.compressed_valid;

	keccak_xif_cid #(
		.copro_compressed_resp_t 	(keccak_xif_instr_pkg::copro_compressed_resp_t),
		.NbInstr					(keccak_xif_instr_pkg::NbCompInstr),
		.CoproInstr					(keccak_xif_instr_pkg::CoproCompInstr),
		.x_compressed_req_t			(x_compressed_req_t),
		.x_compressed_resp_t		(x_compressed_resp_t)
	) i_cid (
		.clk_i (clk_i),
		.rst_ni (rst_ni),
		.compressed_valid_i (compressed_valid),
		.compressed_req_i (compressed_req),
		.compressed_ready_o (compressed_ready),
		.compressed_resp_o (compressed_resp)
	);

	assign cvxif_resp_o.compressed_resp = compressed_resp;
	assign cvxif_resp_o.compressed_ready = compressed_ready;

endmodule