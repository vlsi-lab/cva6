# Out-of-context synthesis of kecc_aes_k_axi_top (top = kecc_aes_k_axi_synth_top,
# a thin type-binding wrapper -- see ../rtl/kecc_aes_k_axi_synth_top.sv).
# No pin constraints, no bitstream -- an area/timing comparison tool for the
# loosely-coupled AXI accelerator INCLUDING its axi_to_reg + reggen register
# file wrapper (not just the bare keccak_aes_k_top core, which
# kecc-aes-k/fpga/scripts/run_synth.tcl already measures separately).
#
# Positional -tclargs (all required, in order):
#   1. proj_root    : Windows path to the cva6-kecc-aes-k/cva6 repo root
#   2. part         : Vivado part to target (CW305 = xc7a100tftg256-2)
#   3. clk_period   : target clock period in ns for the virtual clock on `clk_i`
#   4. version       : v2 | v3 | v4 | v5 -- selects kecc_aes_k_axi/hw/rtl/<version>/
#                      and the matching KECC_AES_K_LOOSE_<version> define
#   5. sbox_impl    : 0 = SERIAL_ROM, 1 = DP_ROM, 2 = BP (v4/v5 only, ignored by v2/v3)
#   6. parallel_slices : v5 only, ignored otherwise
#   7. variant_name : human-readable tag used for the report/checkpoint dir
#                     (e.g. v2, v4_serial_rom, v5_bp)
#   8. wrapper      : kecc_aes_k_axi (default, non-unified) or
#                      kecc_aes_k_axi_unified (area-optimized, see
#                      kecc_aes_k_axi/hw/rtl/v2_unified/keccak_aes_k_top_unified.sv) --
#                      selects which reg_pkg/reg_top/top.sv file set gets
#                      compiled, same AES_LOOSE_WRAPPER mechanism
#                      core/Flist.cva6 uses for simulation.

set proj_root        [lindex $argv 0]
set part             [lindex $argv 1]
set clk_period       [lindex $argv 2]
set version          [lindex $argv 3]
set sbox_impl        [lindex $argv 4]
set parallel_slices  [lindex $argv 5]
set variant_name     [lindex $argv 6]
set wrapper          [lindex $argv 7]
if {$wrapper eq ""} { set wrapper "kecc_aes_k_axi" }

set top "kecc_aes_k_axi_synth_top"

cd $proj_root/kecc_aes_k_axi/synth_area

set work_dir    "work_${variant_name}"
set reports_dir "reports_${variant_name}"
file mkdir $work_dir
file mkdir $reports_dir

create_project -in_memory -part $part synth_${variant_name}

# Read kecc_aes_k_axi/hw/rtl/<version>.flist directly and resolve its
# ${CVA6_REPO_DIR} tokens against $proj_root -- same file the real
# Verilator simulation build uses (core/Flist.cva6 -F's it), so this list
# can never drift from what's actually simulated/verified.
set flist_path "$proj_root/kecc_aes_k_axi/hw/rtl/${version}.flist"
set fp [open $flist_path "r"]
set version_rtl_files [list]
set version_defines [list]
while {[gets $fp line] >= 0} {
    set line [string trim $line]
    if {$line eq "" || [string range $line 0 1] eq "//"} { continue }
    # v4/v5's flist carries a `+define+AES_SBOX_MEM_PATH=...` line (not a
    # file path) -- route it to verilog_define like KECC_AES_K_LOOSE_*
    # below, instead of treating it as a source file.
    if {[string range $line 0 7] eq "+define+"} {
        # The flist's \"..\" escaping is a Verilator -f-parser-specific
        # workaround (its parser strips plain quotes from +define+ values,
        # see the flist's own header comment) -- Vivado's verilog_define
        # property doesn't go through that parser, so the backslashes must
        # come off here or they'd be taken as literal characters in the
        # macro text instead of quote-escapes.
        set define_text [string map {{\"} {"}} [string range $line 8 end]]
        lappend version_defines $define_text
        continue
    }
    # string map (not regsub -all): regsub's replacement argument treats a
    # leading "\\" specially and collapses it to "\", which corrupts a
    # Windows UNC proj_root like \\wsl.localhost\Ubuntu\... -- string map
    # does a literal, non-backslash-interpreting substitution instead.
    set resolved [string map [list {${CVA6_REPO_DIR}} $proj_root] $line]
    lappend version_rtl_files $resolved
}
close $fp

# axi_to_reg/axi_to_axi_lite/axi_atop_filter chain through a long, easy-to-
# miss tail of pulp-platform common_cells helper modules (stream_register ->
# fifo_v2 -> fifo_v3, etc). This explicit list is the axi/src +
# common_cells/src (incl. deprecated/) closure Verilator's own real build
# needed for this exact wrapper module, extracted from
# work-ver/Variane_testharness__verFiles.dat -- NOT a `glob`: Vivado's Tcl
# `glob` silently returns 0 matches against the \\wsl.localhost\... UNC path
# proj_root resolves to on this Windows-hosted Vivado (confirmed via a
# [llength] probe -- no error, just an empty list), so it can't be used here.
# axi_pkg.sv is listed first (and separately from the rest, further down)
# since it must be read/elaborated before ariane_axi_pkg.sv/
# ariane_axi_soc_pkg.sv, which reference axi_pkg:: types -- Vivado's
# elaboration order follows read_verilog's file order for packages, not
# just update_compile_order's auto-detected topological order.
set common_cells_files [list \
    "$proj_root/vendor/pulp-platform/common_cells/src/id_queue.sv" \
    "$proj_root/vendor/pulp-platform/common_cells/src/onehot_to_bin.sv" \
    "$proj_root/vendor/pulp-platform/common_cells/src/addr_decode.sv" \
    "$proj_root/vendor/pulp-platform/common_cells/src/cdc_2phase.sv" \
    "$proj_root/vendor/pulp-platform/common_cells/src/cf_math_pkg.sv" \
    "$proj_root/vendor/pulp-platform/common_cells/src/counter.sv" \
    "$proj_root/vendor/pulp-platform/common_cells/src/delta_counter.sv" \
    "$proj_root/vendor/pulp-platform/common_cells/src/deprecated/fifo_v1.sv" \
    "$proj_root/vendor/pulp-platform/common_cells/src/deprecated/fifo_v2.sv" \
    "$proj_root/vendor/pulp-platform/common_cells/src/edge_detect.sv" \
    "$proj_root/vendor/pulp-platform/common_cells/src/exp_backoff.sv" \
    "$proj_root/vendor/pulp-platform/common_cells/src/fifo_v3.sv" \
    "$proj_root/vendor/pulp-platform/common_cells/src/lfsr.sv" \
    "$proj_root/vendor/pulp-platform/common_cells/src/lfsr_16bit.sv" \
    "$proj_root/vendor/pulp-platform/common_cells/src/lfsr_8bit.sv" \
    "$proj_root/vendor/pulp-platform/common_cells/src/lzc.sv" \
    "$proj_root/vendor/pulp-platform/common_cells/src/popcount.sv" \
    "$proj_root/vendor/pulp-platform/common_cells/src/rr_arb_tree.sv" \
    "$proj_root/vendor/pulp-platform/common_cells/src/rstgen.sv" \
    "$proj_root/vendor/pulp-platform/common_cells/src/rstgen_bypass.sv" \
    "$proj_root/vendor/pulp-platform/common_cells/src/shift_reg.sv" \
    "$proj_root/vendor/pulp-platform/common_cells/src/spill_register.sv" \
    "$proj_root/vendor/pulp-platform/common_cells/src/spill_register_flushable.sv" \
    "$proj_root/vendor/pulp-platform/common_cells/src/stream_arbiter.sv" \
    "$proj_root/vendor/pulp-platform/common_cells/src/stream_arbiter_flushable.sv" \
    "$proj_root/vendor/pulp-platform/common_cells/src/stream_delay.sv" \
    "$proj_root/vendor/pulp-platform/common_cells/src/stream_demux.sv" \
    "$proj_root/vendor/pulp-platform/common_cells/src/stream_mux.sv" \
    "$proj_root/vendor/pulp-platform/common_cells/src/stream_register.sv" \
    "$proj_root/vendor/pulp-platform/common_cells/src/sync.sv" \
    "$proj_root/vendor/pulp-platform/common_cells/src/sync_wedge.sv" \
    "$proj_root/vendor/pulp-platform/common_cells/src/unread.sv" \
]
set axi_files [list \
    "$proj_root/vendor/pulp-platform/axi/src/axi_atop_filter.sv" \
    "$proj_root/vendor/pulp-platform/axi/src/axi_burst_splitter.sv" \
    "$proj_root/vendor/pulp-platform/axi/src/axi_cut.sv" \
    "$proj_root/vendor/pulp-platform/axi/src/axi_delayer.sv" \
    "$proj_root/vendor/pulp-platform/axi/src/axi_demux.sv" \
    "$proj_root/vendor/pulp-platform/axi/src/axi_err_slv.sv" \
    "$proj_root/vendor/pulp-platform/axi/src/axi_id_prepend.sv" \
    "$proj_root/vendor/pulp-platform/axi/src/axi_join.sv" \
    "$proj_root/vendor/pulp-platform/axi/src/axi_multicut.sv" \
    "$proj_root/vendor/pulp-platform/axi/src/axi_mux.sv" \
    "$proj_root/vendor/pulp-platform/axi/src/axi_to_axi_lite.sv" \
    "$proj_root/vendor/pulp-platform/axi/src/axi_xbar.sv" \
]

set rtl_files [concat [list \
    "$proj_root/core/include/config_pkg.sv" \
    "$proj_root/core/include/cv64a6_imac_crypto_loose_v2_config_pkg.sv" \
    "$proj_root/corev_apu/tb/ariane_soc_pkg.sv" \
    "$proj_root/vendor/pulp-platform/axi/src/axi_pkg.sv" \
    "$proj_root/corev_apu/tb/ariane_axi_pkg.sv" \
    "$proj_root/corev_apu/tb/ariane_axi_soc_pkg.sv" \
    "$proj_root/corev_apu/register_interface/vendor/lowrisc_opentitan/src/prim_subreg_arb.sv" \
    "$proj_root/corev_apu/register_interface/vendor/lowrisc_opentitan/src/prim_subreg.sv" \
    "$proj_root/kecc_aes_k_axi/hw/regs/gen/${wrapper}_reg_pkg.sv" \
    "$proj_root/kecc_aes_k_axi/hw/regs/gen/${wrapper}_reg_top.sv" \
] $common_cells_files $axi_files [list \
    "$proj_root/corev_apu/register_interface/src/axi_lite_to_reg.sv" \
    "$proj_root/corev_apu/register_interface/src/axi_to_reg.sv" \
] $version_rtl_files [list \
    "$proj_root/kecc_aes_k_axi/hw/${wrapper}_top.sv" \
    "$proj_root/kecc_aes_k_axi/synth_area/rtl/kecc_aes_k_axi_synth_top.sv" \
]]

set_property verilog_define [concat [list "KECC_AES_K_LOOSE_${version}"] $version_defines] [current_fileset]
read_verilog -sv $rtl_files

set_property include_dirs [list \
    "$proj_root/corev_apu/register_interface/include" \
    "$proj_root/corev_apu/register_interface/vendor/lowrisc_opentitan/src" \
    "$proj_root/corev_apu/register_interface/src" \
    "$proj_root/vendor/pulp-platform/axi/include" \
    "$proj_root/vendor/pulp-platform/common_cells/include" \
] [current_fileset]

set_property top $top [current_fileset]
update_compile_order -fileset sources_1

# Out-of-context constraint: a single virtual clock on `clk_i`, no I/O
# delays (no real CW305 pins -- standalone-IP area check, mirrors
# kecc-aes-k/fpga/scripts/run_synth.tcl's xdc).
set xdc_file "$work_dir/ooc_synth.xdc"
set fp [open $xdc_file "w"]
puts $fp "create_clock -name clk_i -period $clk_period \[get_ports clk_i\]"
close $fp
read_xdc $xdc_file

synth_design -top $top -part $part -mode out_of_context \
             -generic SBOX_IMPL=$sbox_impl -generic PARALLEL_SLICES=$parallel_slices

opt_design

# place_design (not just synth_design/opt_design) is needed for the real
# CLB "Slices" packed-utilization number -- see the sibling kecc-aes-k/fpga
# script's comment for why.
place_design

write_checkpoint -force $work_dir/${top}_${variant_name}_synth.dcp
report_utilization -hierarchical -file $reports_dir/${top}.utilization.rpt
report_utilization                -file $reports_dir/${top}.utilization_summary.rpt
report_timing_summary            -file $reports_dir/${top}.timing_summary.rpt
report_timing -max_paths 20 -nworst 20 -delay_type max -sort_by slack \
                                 -file $reports_dir/${top}.timing_WORST_20.rpt
puts "\[SYNTH\] Done. variant=$variant_name version=$version wrapper=$wrapper SBOX_IMPL=$sbox_impl PARALLEL_SLICES=$parallel_slices  Checkpoint: $work_dir/${top}_${variant_name}_synth.dcp"
