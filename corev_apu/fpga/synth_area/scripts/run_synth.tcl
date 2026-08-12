# Out-of-context synthesis of the CVA6 core (`ariane`) plus the vrf_ip
# accelerator (`vrf_axi_top`), wrapped by vrf_synth_top (see
# ../rtl/vrf_synth_top.sv). Area/timing check only -- no board pins, no
# bitstream.
#
# RTL file list: ../../../core/Flist.cva6 (the actively-maintained
# "CORE-ONLY manifest", parameterized by ${CVA6_REPO_DIR}/${TARGET_CFG}).
# core/Flist.cva6 is core-only (no corev_apu debug module/clint/plic --
# `ariane` doesn't instantiate any of those either) but already lists every
# vrf_ip/rtl/*.sv file and vrf_ip/gen/vrf_reg_{pkg,top}.sv, so it needs no
# extra entries for the accelerator itself -- only the files it doesn't
# cover that vrf_synth_top needs: corev_apu/tb/ariane_axi_pkg.sv (the
# ariane_axi::req_t/resp_t types both ariane's noc port and vrf_axi_top's
# slave port use here), corev_apu/src/ariane.sv itself, and the rest of
# vendor/pulp-platform/axi/src/ (a dependency chain starting from
# corev_apu/register_interface/src/axi_to_reg.sv, which core/Flist.cva6
# DOES list at line 131 -- but axi_to_reg.sv's own axi_to_axi_lite.sv
# dependency, in turn needing axi_atop_filter.sv/axi_burst_splitter.sv,
# is not covered by the core-only manifest at all. Confirmed by two real
# Vivado elaboration failures in a row ("module 'axi_to_axi_lite' not
# found", then "module 'axi_atop_filter' not found"), not assumed --
# rather than keep chasing this one file at a time, every file in that
# vendor directory is included except axi_pkg.sv (already covered by
# core/Flist.cva6 line 92 -- listing it twice would be a duplicate-module
# error), axi_intf.sv (an SV-interface-based wrapper nothing in this
# struct-typed design uses), and axi_test.sv/axi_sim_mem.sv
# (simulation-only testbench utilities, not synthesizable).
#
# ${TARGET_CFG} is resolved to cv64a6_imac_crypto -- the config this
# project's RTL simulation work uses throughout (see IMPLEMENTATION.md),
# since vrf_synth_top's CVA6Cfg parameter binds to whichever
# cva6_config_pkg ends up compiled into the run. That config sets
# DCacheType = WT, so this script also drops core/Flist.cva6's hpdcache
# block (external submodule, its own nested `-F .../hpdcache.Flist`, and
# env-var-rooted RTL files) -- the HPDCACHE-only cache_subsystem modules it
# feeds are behind an elaboration-time `generate if (CVA6Cfg.DCacheType ==
# ...)` that a WT config never takes, so Vivado never needs those files to
# exist.
#
# common/local/util/tc_sram_wrapper.sv (the WT dcache's tag/data SRAMs go
# through this) wraps the technology-agnostic vendor/pulp-platform/
# tech_cells_generic tc_sram inside `// synthesis translate_off` -- it's a
# simulation-only behavioral model, deliberately excluded from synthesis
# upstream, which leaves `tc_sram_wrapper` an empty/undefined black box for
# Vivado (DRC INBB-3). This script swaps it (and tc_sram.sv, its only
# consumer) for common/local/util/tc_sram_fpga_wrapper.sv -- the
# module-for-module Xilinx replacement, backed by the inferable
# vendor/pulp-platform/fpga-support/rtl/SyncSpRamBeNx64.sv.
#
# Positional -tclargs (all required, in order):
#   1. proj_root  : Windows path to this cva6 repo root
#                   (e.g. \\wsl.localhost\Ubuntu\...\digsig\cva6)
#   2. part       : Vivado part to target (CW305 = xc7a100tftg256-2)
#   3. clk_period : target clock period in ns for the virtual clock on clk_i

set proj_root  [lindex $argv 0]
set part       [lindex $argv 1]
set clk_period [lindex $argv 2]

set top        "vrf_synth_top"
set target_cfg "cv64a6_imac_crypto"

set extra_files [list \
    "$proj_root/corev_apu/tb/ariane_axi_pkg.sv" \
    "$proj_root/corev_apu/src/ariane.sv" \
    "$proj_root/common/local/util/tc_sram_fpga_wrapper.sv" \
    "$proj_root/vendor/pulp-platform/fpga-support/rtl/SyncSpRamBeNx64.sv" \
    "$proj_root/corev_apu/fpga/synth_area/rtl/vrf_synth_top.sv" \
]

# Whole-directory bundles for vendor/pulp-platform/{axi,common_cells}/src
# (plus common_cells/src/deprecated, still-used legacy modules like
# fifo_v2.sv that were never migrated into src/ proper): core/Flist.cva6
# already lists some files from each (CVA6's own direct dependencies), but
# not the further dependency chain register_interface's axi_to_reg.sv ->
# axi_to_axi_lite.sv -> axi_atop_filter.sv/axi_burst_splitter.sv ->
# stream_register.sv -> fifo_v2.sv needs, which core/Flist.cva6 (a
# core-only manifest) never anticipated. Confirmed by four real Vivado
# elaboration failures in a row (one missing module at a time --
# axi_to_axi_lite, axi_atop_filter, stream_register, fifo_v2), not assumed
# -- rather than keep chasing individual files, all three directories are
# bundled here (added below, after Flist.cva6 is parsed, and de-duplicated
# by basename against whatever Flist.cva6 already provided -- read_verilog
# errors on a module defined twice).
set dir_bundle_excludes [list \
    axi_pkg.sv axi_intf.sv axi_test.sv axi_sim_mem.sv \
]

# Dropped from core/Flist.cva6's own list (exact file matches, not
# substrings -- tc_sram_wrapper_cache_techno.sv must NOT be caught here):
# the simulation-only tc_sram_wrapper.sv this is replacing, and tc_sram.sv,
# its only consumer (nothing else in this file list uses tc_sram directly).
set dropped_files [list \
    "common/local/util/tc_sram_wrapper.sv" \
    "vendor/pulp-platform/tech_cells_generic/src/rtl/tc_sram.sv" \
]

# Vivado's default cwd when launched through cmd.exe on this machine is
# C:\Windows (no write permission there) -- cd into this flow's own dir so
# the relative work_dir/reports_dir mkdir below actually succeeds.
cd $proj_root/corev_apu/fpga/synth_area

set work_dir    "work"
set reports_dir "reports"
file mkdir $work_dir
file mkdir $reports_dir

create_project -in_memory -part $part synth_${top}

# --- Parse core/Flist.cva6 ---------------------------------------------
# +incdir+ lines become include dirs; ${CVA6_REPO_DIR}/${TARGET_CFG}
# substituted; any hpdcache-related line (its own `-F` sub-manifest, or a
# ${HPDCACHE_DIR}-rooted file) is dropped, see header comment above.
set incdirs   {}
set rtl_files {}

set flist_fp [open "$proj_root/core/Flist.cva6" "r"]
while {[gets $flist_fp line] >= 0} {
    set line [string trim $line]
    if {$line eq ""} {
        continue
    }
    if {[string match "//*" $line]} {
        continue
    }
    if {[string match "-F *" $line]} {
        continue
    }
    if {[string match "*HPDCACHE_DIR*" $line] || [string match "*hpdcache*" $line]} {
        continue
    }
    set is_dropped 0
    foreach d $dropped_files {
        if {$line eq "\$\{CVA6_REPO_DIR\}/$d"} {
            set is_dropped 1
            break
        }
    }
    if {$is_dropped} {
        continue
    }
    # string map, not regsub: $proj_root is a Windows UNC path full of
    # backslashes, which regsub's subspec argument would reinterpret as
    # backreferences/escapes instead of literal characters.
    set line [string map [list {${CVA6_REPO_DIR}} $proj_root {${TARGET_CFG}} $target_cfg] $line]
    if {[string match "+incdir+*" $line]} {
        lappend incdirs [string range $line [string length "+incdir+"] end]
        continue
    }
    lappend rtl_files $line
}
close $flist_fp

foreach f $extra_files {
    lappend rtl_files $f
}

# Existing basenames (from Flist.cva6 + extra_files so far), so the whole-
# directory bundles below add only what's not already present.
set have_basenames {}
foreach f $rtl_files {
    lappend have_basenames [file tail $f]
}

foreach dir [list \
    "$proj_root/vendor/pulp-platform/axi/src" \
    "$proj_root/vendor/pulp-platform/common_cells/src" \
    "$proj_root/vendor/pulp-platform/common_cells/src/deprecated" \
] {
    foreach f [glob -directory $dir "*.sv"] {
        set bn [file tail $f]
        if {[lsearch -exact $dir_bundle_excludes $bn] >= 0} {
            continue
        }
        if {[lsearch -exact $have_basenames $bn] >= 0} {
            continue
        }
        lappend rtl_files $f
        lappend have_basenames $bn
    }
}

set_property include_dirs $incdirs [current_fileset]
read_verilog $rtl_files

set_property top $top [current_fileset]
update_compile_order -fileset sources_1

# Out-of-context constraint: a single virtual clock on clk_i, no I/O delays
# (no real CW305 pins are involved -- this is a core+accelerator area
# check, not a bootable/flashable build).
set xdc_file "$work_dir/ooc_synth.xdc"
set fp [open $xdc_file "w"]
puts $fp "create_clock -name clk_i -period $clk_period \[get_ports clk_i\]"
close $fp
read_xdc $xdc_file

synth_design -top $top -part $part -mode out_of_context

opt_design

write_checkpoint -force $work_dir/${top}_synth.dcp

# Full hierarchical breakdown -- this single report is what
# scripts/report_area.py parses to pull out the headline numbers (whole
# system / CVA6 core alone / vrf_ip accelerator alone, and per-job-front-end
# within it), see instance paths noted in ../rtl/vrf_synth_top.sv.
report_utilization -hierarchical -file $reports_dir/${top}.utilization.rpt
report_timing_summary            -file $reports_dir/${top}.timing_summary.rpt
report_timing -max_paths 20 -nworst 20 -delay_type max -sort_by slack \
                                 -file $reports_dir/${top}.timing_WORST_20.rpt
puts "\[SYNTH\] Done. Checkpoint: $work_dir/${top}_synth.dcp"