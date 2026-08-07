// One lane's slice-serial storage: DEPTH-deep, WIDTH-bit-wide, one
// synchronous write port, two independent asynchronous read ports (needed
// because rho's rotation, when it isn't a multiple of PARALLEL_SLICES,
// straddles two adjacent slice addresses -- see keccak_slice_serial.sv).
`default_nettype none

module keccak_lane_mem #(
    parameter int unsigned WIDTH  = 4,
    parameter int unsigned DEPTH  = 16,
    parameter int unsigned ADDR_W = 4
) (
    input  wire                   clk,
    input  wire                   we,
    input  wire [ADDR_W-1 : 0]    waddr,
    input  wire [WIDTH-1 : 0]     wdata,
    input  wire [ADDR_W-1 : 0]    raddr0,
    output wire [WIDTH-1 : 0]     rdata0,
    input  wire [ADDR_W-1 : 0]    raddr1,
    output wire [WIDTH-1 : 0]     rdata1
);

  reg [WIDTH-1 : 0] mem [0 : DEPTH-1];

  always @(posedge clk)
    if (we)
      mem[waddr] <= wdata;

  assign rdata0 = mem[raddr0];
  assign rdata1 = mem[raddr1];

endmodule
