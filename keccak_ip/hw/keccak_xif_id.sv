// Keccak Accelerator IP - Tightly
// Module description for XIF instruction decoder 
// Author: Federico Runco

module keccak_xif_id #(
	parameter type					copro_issue_resp_t	= logic,
	parameter type					opcode_t			= logic,
	parameter int					NbInstr				= 1,
	parameter copro_issue_resp_t	CoproInstr[NbInstr]	= {0},
	parameter int unsigned			NrRgprPorts			= 2,
	parameter type					hartid_t			= logic,
	parameter type					id_t				= logic,
	parameter type					x_issue_req_t		= logic,
	parameter type					x_issue_resp_t		= logic,
	parameter type					x_register_t		= logic,
	parameter type					registers_t			= logic
) (
	input	logic			clk_i,
	input	logic			rst_ni,
	input	logic			issue_valid_i,
	input	x_issue_req_t	issue_req_i,
	output	logic			issue_ready_o,
	output	x_issue_resp_t	issue_resp_o,
	input	logic			register_valid_i,
	input	x_register_t	register_i,
	output	registers_t		registers_o,
	output	opcode_t		opcode_o,
	output	hartid_t		hartid_o,
	output	id_t			id_o,
	output	logic[4:0]		rd_o
);
	logic [NbInstr-1:0] instr;
	logic [2:0] reg_rdy;

	// Internal OHE, encodes if the instruction matches one of the supported ones
	for (genvar i = 0; i < NbInstr; i++) begin
		assign instr[i] = (CoproInstr[i].mask & issue_req_i.instr) == CoproInstr[i].instr;
	end

	always_comb begin
		reg_rdy[0]					= '0;
		reg_rdy[1]					= '0;
		reg_rdy[2]					= '0;
		issue_ready_o				= '0;
		issue_resp_o.accept 		= '0;
		issue_resp_o.writeback		= '0;
		issue_resp_o.register_read	= '0;
		registers_o					= '0;
		opcode_o					= opcode_t'(0);
		hartid_o					= '0;
		id_o						= '0;
		rd_o						= '0;

		for (int i = 0; i < NbInstr; i++) begin
			// Check if instruction matches coprocessor ones and CPU is offloading exectution
			if (instr[i] && issue_valid_i) begin
				// If instruction is supported, fill response fields from package
				issue_resp_o.accept = CoproInstr[i].resp.accept;
				issue_resp_o.writeback = CoproInstr[i].resp.writeback;
				issue_resp_o.register_read = CoproInstr[i].resp.register_read;

				// If registers are needed, wait for them to be ready before asserting issue_ready_o
				if (issue_resp_o.accept) begin
					reg_rdy[0] = (~CoproInstr[i].resp.register_read[0] || register_i.rs_valid[0]); 
					reg_rdy[1] = (~CoproInstr[i].resp.register_read[1] || register_i.rs_valid[1]); 
					if (NrRgprPorts == 3) 	reg_rdy[2] = (~CoproInstr[i].resp.register_read[2] || register_i.rs_valid[2]);
					else 					reg_rdy[2] = 1'b1;

					issue_ready_o = reg_rdy[0] && reg_rdy[1] && reg_rdy[2];
				end

				opcode_o = CoproInstr[i].opcode;
				id_o = issue_req_i.id;
				hartid_o = issue_req_i.hartid;
				rd_o = issue_req_i.instr[11:7];

				for (int j = 0; j < NrRgprPorts; j++) begin
					if (issue_resp_o.register_read[j]) 	registers_o[j] = register_i.rs[j];
					else 								registers_o[j] = '0;
				end
			end
		end

		// If instruction has not been matched and CPU is offloading execution, still assert ready (raises ILLEGAL_INSTR ?)
		if (issue_valid_i && ~(|instr)) issue_ready_o = 1'b1;
	end

	// TODO: verification assertions
endmodule