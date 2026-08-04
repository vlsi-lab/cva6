#!/usr/bin/env bash
# Out-of-context Vivado synthesis driver for ariane_synth_top (CVA6 core +
# kecc_aes_k_xif coprocessor). No CW305 pins, no bitstream -- see README.md.
#
# Vivado itself is a Windows install on this machine (WSL) -- see
# ~/bin/vivado for the cmd.exe wrapper this script calls through.
#
# Usage:
#   ./run_synth.sh
#   CLK_PERIOD_NS=8 ./run_synth.sh                # override the default 10ns/100MHz target
#   XILINX_PART=xc7a35tcpg236-1 ./run_synth.sh     # override the CW305 default part

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

: "${XILINX_PART:=xc7a100tftg256-2}"   # CW305: Artix-7 100T, ftg256 package
: "${CLK_PERIOD_NS:=10}"               # 100 MHz virtual clock (area-focused OOC synth, not timing-critical)
VIVADO="$HOME/bin/vivado"

PROJ_ROOT_WIN="$(wslpath -w "$REPO_ROOT")"
TCL_SCRIPT_WIN="$(wslpath -w "$SCRIPT_DIR/scripts/run_synth.tcl")"

mkdir -p "$SCRIPT_DIR/logs"

echo "[run_synth] ariane_synth_top: CVA6 + kecc_aes_k_xif (part=${XILINX_PART}, clk=${CLK_PERIOD_NS}ns)"
"$VIVADO" -mode batch -nojournal \
    -log "${PROJ_ROOT_WIN}\\corev_apu\\fpga\\synth_area\\logs\\synth.log" \
    -source "$TCL_SCRIPT_WIN" \
    -tclargs "$PROJ_ROOT_WIN" "$XILINX_PART" "$CLK_PERIOD_NS"

echo "[run_synth] Reports: $SCRIPT_DIR/reports/"
echo "[run_synth] Area summary: run scripts/report_area.py to extract the 3-way (system / cva6 / coprocessor) breakdown"
