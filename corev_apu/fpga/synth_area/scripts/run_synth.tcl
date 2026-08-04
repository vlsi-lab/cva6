# Out-of-context synthesis of the CVA6 core (`ariane`) with the
# kecc_aes_k_xif coprocessor tightly-coupled via CV-X-IF, wrapped by
# ariane_synth_top (see ../rtl/ariane_synth_top.sv). Area/timing check only
# -- no board pins, no bitstream. Mirrors the out-of-context pattern used
# for keccak_aes_k_top in the sibling kecc-aes-k repo's fpga/ flow.
#
# RTL file list: ../../../core/Flist.cva6 (the actively-maintained
# "CORE-ONLY manifest", parameterized by ${CVA6_REPO_DIR}/${TARGET_CFG} --
# NOT Flist.ariane one directory up, which as of this writing references
# several files that no longer exist in this checkout, e.g.
# core/include/acc_pkg.sv, core/mmu_sv39/*.sv, core/include/cvxif_pkg.sv --
# stale relative to the current core/cva6_mmu/ layout and macro-based
# cvxif_types.svh). core/Flist.cva6 is core-only (no corev_apu debug
# module/clint/plic -- `ariane` doesn't instantiate any of those either),
# so this script adds exactly the two files core/Flist.cva6 doesn't cover
# that `ariane_synth_top` needs: corev_apu/tb/ariane_axi_pkg.sv (the
# `ariane_axi::req_t`/`resp_t` types on ariane's noc_req_o/noc_resp_i
# ports) and corev_apu/src/ariane.sv itself.
#
# ${TARGET_CFG} is resolved to cv64a6_imac_crypto -- the only config in
# this repo with CvxifEn == 1 and CoproType == COPRO_KECC_AES_K (see
# kecc_aes_k_xif/README.md), and the same config this repo's own
# verif/sim/cva6.py-driven tests (tests/keccak64/run.sh,
# tests/ml-kem-512/run.sh) already use -- since ariane_synth_top's CVA6Cfg
# parameter binds to whichever cva6_config_pkg ends up compiled into the
# run. That config sets DCacheType = WT, so this script also drops
# core/Flist.cva6's hpdcache block (external submodule, its own nested
# `-F .../hpdcache.Flist`, and 4 env-var-rooted RTL files) -- the
# HPDCACHE-only cache_subsystem modules it feeds are behind an
# elaboration-time `generate if (CVA6Cfg.DCacheType == ...)` that a WT
# config never takes, so Vivado never needs those files to exist.
#
# common/local/util/tc_sram_wrapper.sv (the WT dcache's tag/data SRAMs go
# through this) wraps the technology-agnostic vendor/pulp-platform/
# tech_cells_generic tc_sram inside `// synthesis translate_off` -- it's a
# simulation-only behavioral model, deliberately excluded from synthesis
# upstream, which leaves `tc_sram_wrapper` an empty/undefined black box for
# Vivado (DRC INBB-3). This script swaps it (and tc_sram.sv, its only
# consumer) for common/local/util/tc_sram_fpga_wrapper.sv -- the
# module-for-module Xilinx replacement Bender.yml's own
# `target: all(fpga, xilinx)` selects for exactly this situation -- backed
# by the inferable vendor/pulp-platform/fpga-support/rtl/SyncSpRamBeNx64.sv
# (defaults to FPGA_TARGET_XILINX when nothing else is defined).
#
# Positional -tclargs (all required, in order):
#   1. proj_root  : Windows path to the cva6-kecc-aes-k/cva6 repo root
#                   (e.g. \\wsl.localhost\Ubuntu\...\cva6-kecc-aes-k\cva6)
#   2. part       : Vivado part to target (CW305 = xc7a100tftg256-2)
#   3. clk_period : target clock period in ns for the virtual clock on clk_i

set proj_root  [lindex $argv 0]
set part       [lindex $argv 1]
set clk_period [lindex $argv 2]

set top        "ariane_synth_top"
set target_cfg "cv64a6_imac_crypto"

set extra_files [list \
    "$proj_root/corev_apu/tb/ariane_axi_pkg.sv" \
    "$proj_root/corev_apu/src/ariane.sv" \
    "$proj_root/common/local/util/tc_sram_fpga_wrapper.sv" \
    "$proj_root/vendor/pulp-platform/fpga-support/rtl/SyncSpRamBeNx64.sv" \
    "$proj_root/corev_apu/fpga/synth_area/rtl/ariane_synth_top.sv" \
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

set_property include_dirs $incdirs [current_fileset]
read_verilog $rtl_files

set_property top $top [current_fileset]
update_compile_order -fileset sources_1

# Out-of-context constraint: a single virtual clock on clk_i, no I/O delays
# (no real CW305 pins are involved -- this is a core+coprocessor area check,
# not a bootable/flashable build).
set xdc_file "$work_dir/ooc_synth.xdc"
set fp [open $xdc_file "w"]
puts $fp "create_clock -name clk_i -period $clk_period \[get_ports clk_i\]"
close $fp
read_xdc $xdc_file

synth_design -top $top -part $part -mode out_of_context

opt_design

write_checkpoint -force $work_dir/${top}_synth.dcp

# Full hierarchical breakdown -- this single report is what
# scripts/report_area.py parses to pull out the three headline numbers
# (whole system / CVA6 core alone / coprocessor alone), see instance paths
# noted in ../rtl/ariane_synth_top.sv.
report_utilization -hierarchical -file $reports_dir/${top}.utilization.rpt
report_timing_summary            -file $reports_dir/${top}.timing_summary.rpt
report_timing -max_paths 20 -nworst 20 -delay_type max -sort_by slack \
                                 -file $reports_dir/${top}.timing_WORST_20.rpt
puts "\[SYNTH\] Done. Checkpoint: $work_dir/${top}_synth.dcp"
