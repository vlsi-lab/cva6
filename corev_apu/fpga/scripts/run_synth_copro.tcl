# Out-of-context synthesis of the HASH_IP coprocessor only
# (top = hash_xif_synth_top). No CVA6 core, no SoC, no IPs.
#
# Required env vars:
#   XILINX_PART     : Vivado part to target (e.g. xc7a100tftg256-2)
#   CLK_PERIOD_NS   : Target clock period in ns for clk_i
#   COPRO_TOP       : (optional) override the top module
#                     (default: hash_xif_synth_top)
#   CVA6_REPO_DIR   : Absolute path to the cva6 repo root

set part        $::env(XILINX_PART)
set clk_period  $::env(CLK_PERIOD_NS)
set repo_dir    $::env(CVA6_REPO_DIR)
if {[info exists ::env(COPRO_TOP)]} {
  set top $::env(COPRO_TOP)
} else {
  set top "hash_xif_synth_top"
}
if {[info exists ::env(TARGET_CFG)]} {
  set target_cfg $::env(TARGET_CFG)
} else {
  set target_cfg "cv64a6_imafdc_sv39"
}

set work_dir "work-fpga-copro"
file mkdir $work_dir
file mkdir reports_copro

# In-memory project
create_project -in_memory -part $part synth_copro

# Include directories needed by cvxif_types.svh + hash sources
set_property include_dirs [list \
    "${repo_dir}/core/include" \
    "${repo_dir}/vendor/pulp-platform/common_cells/include" \
    "${repo_dir}/vendor/pulp-platform/axi/include" \
    "${repo_dir}/hash_ip/hw/include" \
] [current_fileset]

# -------------------------------------------------------------------------
# Minimal package set: just enough to build the cvxif macros against a real
# CVA6 config. We do NOT pull in the whole CVA6 Flist, otherwise Vivado
# would also try to synthesize unrelated core modules (icache, etc.).
# -------------------------------------------------------------------------
set pkg_files [list \
    "${repo_dir}/core/include/riscv_pkg.sv" \
    "${repo_dir}/core/include/config_pkg.sv" \
    "${repo_dir}/core/include/${target_cfg}_config_pkg.sv" \
    "${repo_dir}/core/include/ariane_pkg.sv" \
    "${repo_dir}/core/include/build_config_pkg.sv" \
]

# HASH_IP RTL (matches the order used in core/Flist.cva6)
set rtl_files [list \
    "${repo_dir}/hash_ip/hw/include/hash_pkg.sv" \
    "${repo_dir}/hash_ip/hw/keccak/pkg_keccak.sv" \
    "${repo_dir}/hash_ip/hw/keccak/keccak_round_constants_gen.sv" \
    "${repo_dir}/hash_ip/hw/keccak/keccak_round.sv" \
    "${repo_dir}/hash_ip/hw/keccak/keccak_dp.sv" \
    "${repo_dir}/hash_ip/hw/keccak/keccak_cu.sv" \
    "${repo_dir}/hash_ip/hw/keccak/keccak_f.sv" \
    "${repo_dir}/hash_ip/hw/hash_register.sv" \
    "${repo_dir}/hash_ip/hw/chain_lengths.sv" \
    "${repo_dir}/hash_ip/hw/sphincs_ops.sv" \
    "${repo_dir}/hash_ip/hw/hash.sv" \
    "${repo_dir}/hash_ip/hw/hash_xif_id.sv" \
    "${repo_dir}/hash_ip/hw/hash_xif_ex.sv" \
    "${repo_dir}/hash_ip/hw/hash_xif_cid.sv" \
    "${repo_dir}/hash_ip/hw/hash_xif.sv" \
    "${repo_dir}/hash_ip/synth/hash_xif_synth_top.sv" \
]

# Header registered as global include (needed by hash_xif_synth_top)
set headers [list "${repo_dir}/core/include/cvxif_types.svh"]
read_verilog -sv $headers
set hdr_obj [get_files -of_objects [get_filesets sources_1] $headers]
set_property -dict { file_type {Verilog Header} is_global_include 1 } -objects $hdr_obj

read_verilog -sv $pkg_files
read_verilog -sv $rtl_files

set_property top $top [current_fileset]
update_compile_order -fileset sources_1

# Out-of-context constraints: virtual clock on clk_i
set xdc_file "$work_dir/ooc_synth.xdc"
set fp [open $xdc_file "w"]
puts $fp "create_clock -name clk_i -period $clk_period \[get_ports clk_i\]"
close $fp
read_xdc $xdc_file

# -------------------------------------------------------------------------
# Timing-driven synthesis options (push for higher Fmax / lower period)
#   - PerformanceOptimized   : timing-aware synth strategy
#   - retiming               : move FFs across combinational logic to
#                              balance pipeline stages (often the biggest
#                              single win)
#   - flatten_hierarchy full : enable cross-boundary optimization
#   - fsm_extraction one_hot : faster FSM encodings
#   - resource_sharing off   : trade area for speed
#   - no_lc                  : disable LUT combining (helps timing,
#                              costs LUTs)
# Override with -directive Default and remove -retiming if you want a
# more "area" oriented build.
# -------------------------------------------------------------------------
synth_design -top $top -part $part -mode out_of_context \
             -directive PerformanceOptimized \
             -retiming \
             -flatten_hierarchy full \
             -fsm_extraction one_hot \
             -resource_sharing off \
             -no_lc

# Post-synth logic optimization (further timing improvement)
opt_design -directive ExploreWithRemap

# Reports + checkpoint
write_checkpoint -force $work_dir/${top}_synth.dcp
report_utilization -hierarchical -file reports_copro/${top}.utilization.rpt
report_timing_summary            -file reports_copro/${top}.timing_summary.rpt
report_timing -max_paths 100 -nworst 100 -delay_type max -sort_by slack \
                                 -file reports_copro/${top}.timing_WORST_100.rpt
report_design_analysis           -file reports_copro/${top}.design_analysis.rpt
puts "\[SYNTH-COPRO\] Done. Top=$top  Checkpoint: $work_dir/${top}_synth.dcp"
