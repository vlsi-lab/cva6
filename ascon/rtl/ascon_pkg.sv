// Ascon Accelerator IP - Loosely
// Shared typedefs for the Ascon permutation core.
// Ported from the CHIMERA project's ascon_globals.vhd (num_plane/num_sheet=5, N=64).

package ascon_pkg;

  localparam int unsigned NUM_LANE = 5;
  localparam int unsigned LANE_WIDTH = 64;
  localparam int unsigned STATE_WIDTH = NUM_LANE * LANE_WIDTH;

  typedef logic [LANE_WIDTH-1:0] ascon_lane_t;

endpackage
