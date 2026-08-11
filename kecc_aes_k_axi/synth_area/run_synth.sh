#!/usr/bin/env bash
# Out-of-context Vivado synthesis driver for kecc_aes_k_axi_top (the AXI
# wrapper + reggen register file + keccak_aes_k_top core), one run per
# variant -- this is the "how big is the accelerator, considering also the
# wrapper" area measurement. Mirrors ../../kecc-aes-k/fpga/run_synth.sh
# (which measures the bare core alone, no wrapper) and
# ../../corev_apu/fpga/synth_area/run_synth.sh (which measures the whole
# CVA6+ISE-coprocessor system).
#
# Vivado itself is a Windows install on this machine (WSL) -- see
# ~/bin/vivado for the cmd.exe wrapper this script calls through.
#
# Usage:
#   ./run_synth.sh                       # v2 only (baseline pilot)
#   ./run_synth.sh v3
#   ./run_synth.sh v4_serial_rom | v4_dp_rom | v4_bp
#   ./run_synth.sh v5_serial_rom | v5_dp_rom | v5_bp
#   ./run_synth.sh all                   # all 8 variants
#   CLK_PERIOD_NS=8 ./run_synth.sh v2    # override the default 10ns/100MHz target
#   XILINX_PART=xc7a35tcpg236-1 ./run_synth.sh v2   # override the CW305 default part

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

: "${XILINX_PART:=xc7a100tftg256-2}"   # CW305: Artix-7 100T, ftg256 package
: "${CLK_PERIOD_NS:=10}"               # 100 MHz virtual clock -- area-focused OOC synth, not timing closure
VIVADO="$HOME/bin/vivado"

PROJ_ROOT_WIN="$(wslpath -w "$REPO_ROOT")"
TCL_SCRIPT_WIN="$(wslpath -w "$SCRIPT_DIR/scripts/run_synth.tcl")"

mkdir -p "$SCRIPT_DIR/logs"

run_variant() {
    local version="$1" sbox_impl="$2" parallel_slices="$3" variant_name="$4"
    echo "[run_synth] ${variant_name} (version=${version}, SBOX_IMPL=${sbox_impl}, PARALLEL_SLICES=${parallel_slices}, part=${XILINX_PART}, clk=${CLK_PERIOD_NS}ns)"
    "$VIVADO" -mode batch -nojournal \
        -log "${PROJ_ROOT_WIN}\\kecc_aes_k_axi\\synth_area\\logs\\${variant_name}.log" \
        -source "$TCL_SCRIPT_WIN" \
        -tclargs "$PROJ_ROOT_WIN" "$XILINX_PART" "$CLK_PERIOD_NS" "$version" "$sbox_impl" "$parallel_slices" "$variant_name"
}

run_all() {
    run_variant v2 0 4 v2
    run_variant v3 0 4 v3
    run_variant v4 0 4 v4_serial_rom
    run_variant v4 1 4 v4_dp_rom
    run_variant v4 2 4 v4_bp
    run_variant v5 0 4 v5_serial_rom
    run_variant v5 1 4 v5_dp_rom
    run_variant v5 2 4 v5_bp
}

case "${1:-v2}" in
    v2)             run_variant v2 0 4 v2 ;;
    v3)             run_variant v3 0 4 v3 ;;
    v4_serial_rom)  run_variant v4 0 4 v4_serial_rom ;;
    v4_dp_rom)      run_variant v4 1 4 v4_dp_rom ;;
    v4_bp)          run_variant v4 2 4 v4_bp ;;
    v5_serial_rom)  run_variant v5 0 4 v5_serial_rom ;;
    v5_dp_rom)      run_variant v5 1 4 v5_dp_rom ;;
    v5_bp)          run_variant v5 2 4 v5_bp ;;
    all)            run_all ;;
    *)
        echo "Usage: $0 [v2|v3|v4_serial_rom|v4_dp_rom|v4_bp|v5_serial_rom|v5_dp_rom|v5_bp|all]" >&2
        exit 1
        ;;
esac
