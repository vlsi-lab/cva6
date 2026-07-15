#!/bin/bash
#
# Batch-runs the three TPA benchmarks (Keccak-f[1600]/SHAKE128,
# Keccak-f[1600]/SHAKE256, Ascon-p12/Ascon-XOF128), each in both the
# original (pure-software) and optimized (AXI accelerator) builds, on the
# cva6 RTL simulator. Prints a summary table with the measured permutation
# cycle count (C_perm) and, when clock frequency and area are supplied, the
# resulting
#
#   TPA = r * f_clk / (C_perm * A)
#
# TPA is only computed for the "hw" (AXI accelerator) rows -- f_clk/A
# describe the accelerator IP, not the CVA6 core running the "sw" baseline.
# f_clk and A are not observable from RTL simulation (they come from your
# synthesis/FPGA implementation reports), so pass them in per accelerator.
# f_clk is in Hz; area A is in whatever unit your reports use (e.g. LUTs,
# GE, mm^2) -- TPA is then expressed per that same area unit.
#
# Usage:
#   tests/TPA/run_all.sh [--only sw|hw|both] [--timeout SECONDS] \
#     [--keccak-fclk HZ] [--keccak-area AREA] \
#     [--ascon-fclk HZ]  [--ascon-area AREA]
#
# Example:
#   tests/TPA/run_all.sh --keccak-fclk 100000000 --keccak-area 12345 \
#                         --ascon-fclk 150000000  --ascon-area 3210
#
# Run this with `bash`, not `source`/`.` -- it uses `set -u` and `exit`,
# which would otherwise leak nounset into your interactive shell and/or
# close your terminal on an error path.

if (return 0 2>/dev/null); then
  echo "Run this with bash, not 'source': bash ${BASH_SOURCE[0]} $*" >&2
  return 1
fi

set -u

TIMEOUT=1800
ONLY="both"
KECCAK_FCLK=""
KECCAK_AREA=""
ASCON_FCLK=""
ASCON_AREA=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --only)         ONLY="$2"; shift 2 ;;
    --timeout)      TIMEOUT="$2"; shift 2 ;;
    --keccak-fclk)  KECCAK_FCLK="$2"; shift 2 ;;
    --keccak-area)  KECCAK_AREA="$2"; shift 2 ;;
    --ascon-fclk)   ASCON_FCLK="$2"; shift 2 ;;
    --ascon-area)   ASCON_AREA="$2"; shift 2 ;;
    -h|--help)      sed -n '2,24p' "$0"; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

case "$ONLY" in
  sw)   MODES=("");;
  hw)   MODES=("copro");;
  both) MODES=("" "copro");;
  *) echo "--only must be sw, hw, or both (got '$ONLY')" >&2; exit 1 ;;
esac

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT" || exit 1

if [ -z "${RISCV:-}" ]; then
  echo "ERROR: \$RISCV is not set. Export it to your RISC-V toolchain root first, e.g.:" >&2
  echo "  export RISCV=/home/aledolme/tools/riscv64" >&2
  exit 1
fi

TS="$(date +%Y%m%d_%H%M%S)"
RESULTS_DIR="$REPO_ROOT/tests/TPA/bench_results/$TS"
mkdir -p "$RESULTS_DIR"

echo "Results and full logs: $RESULTS_DIR"
echo "Modes: ${MODES[*]:-sw}"
echo "Per-run timeout: ${TIMEOUT}s"
echo

# name|run_dir|r_bits|fclk|area
TESTS=(
  "SHAKE128|tests/TPA/keccak-shake128|1344|$KECCAK_FCLK|$KECCAK_AREA"
  "SHAKE256|tests/TPA/keccak-shake256|1088|$KECCAK_FCLK|$KECCAK_AREA"
  "Ascon-XOF128|tests/TPA/ascon-xof128|64|$ASCON_FCLK|$ASCON_AREA"
)

# name|mode|status|cycles|r_bits|fclk|area|tpa
declare -a SUMMARY

for entry in "${TESTS[@]}"; do
  IFS='|' read -r name run_dir r_bits fclk area <<< "$entry"
  run_sh="$run_dir/run.sh"

  if [ ! -f "$run_sh" ]; then
    echo ">>> SKIP $name: $run_sh not found" >&2
    SUMMARY+=("$name|-|MISSING|-|$r_bits|$fclk|$area|-")
    continue
  fi

  for mode in "${MODES[@]}"; do
    label="sw"; [[ "$mode" == "copro" ]] && label="hw"
    logfile="$RESULTS_DIR/${name}_${label}.log"

    dv_target="$(grep -oP '(?<=^DV_TARGET=)\S+' "$run_sh")"
    run_out_dir="$RESULTS_DIR/${name}_${label}_simout"
    iss_log="$run_out_dir/veri-testharness_sim/main.${dv_target}.log.iss"

    echo "=== [$name / $label] starting ($(date +%H:%M:%S)) ==="
    start=$(date +%s)
    DV_OPTS="-o $run_out_dir" timeout "$TIMEOUT" bash "$run_sh" $mode > "$logfile" 2>&1
    rc=$?
    end=$(date +%s)
    elapsed=$((end - start))

    if [ -f "$iss_log" ]; then
      {
        echo
        echo "----- ISS simulation log ($iss_log) -----"
        cat "$iss_log"
      } >> "$logfile"
    fi

    if [ "$rc" -eq 124 ]; then
      status="TIMEOUT (>${TIMEOUT}s)"
    elif grep -q "Test Successful" "$logfile"; then
      status="PASS"
    elif grep -q "Test FAILED" "$logfile"; then
      status="FAIL (mismatch)"
    elif [ "$rc" -ne 0 ]; then
      status="ERROR (build/sim, rc=$rc)"
    else
      status="UNKNOWN (no Test Successful/FAILED marker)"
    fi

    cycles="$(grep -oE 'cycles permute: [0-9]+' "$logfile" | grep -oE '[0-9]+' | tail -1)"

    tpa="-"
    if [ "$label" = "hw" ] && [ "$status" = "PASS" ] && [ -n "$cycles" ] && [ -n "$fclk" ] && [ -n "$area" ]; then
      tpa="$(awk -v r="$r_bits" -v f="$fclk" -v c="$cycles" -v a="$area" 'BEGIN { printf "%.6g", (r * f) / (c * a) }')"
    fi

    echo "=== [$name / $label] $status  (${elapsed}s, C_perm=${cycles:-?} cycles)  -> $logfile ==="
    echo

    SUMMARY+=("$name|$label|$status ($((elapsed))s)|${cycles:--}|$r_bits|${fclk:--}|${area:--}|$tpa")
  done
done

echo
echo "==================================================== SUMMARY ===================================================="
printf "%-14s %-4s %-22s %-10s %-8s %-14s %-10s %s\n" "TEST" "MODE" "STATUS" "C_PERM" "R(bits)" "F_CLK(Hz)" "AREA" "TPA=r*f_clk/(C_perm*A)"
printf '%s\n' "--------------------------------------------------------------------------------------------------------------------------"
for row in "${SUMMARY[@]}"; do
  IFS='|' read -r n m s c r f a t <<< "$row"
  printf "%-14s %-4s %-22s %-10s %-8s %-14s %-10s %s\n" "$n" "$m" "$s" "$c" "$r" "$f" "$a" "$t"
done
echo "==========================================================================================================================="
echo "Full logs in: $RESULTS_DIR"
if [ -z "$KECCAK_FCLK" ] || [ -z "$KECCAK_AREA" ] || [ -z "$ASCON_FCLK" ] || [ -z "$ASCON_AREA" ]; then
  echo
  echo "Note: TPA left blank where f_clk/area weren't supplied. Re-run with"
  echo "  --keccak-fclk HZ --keccak-area AREA --ascon-fclk HZ --ascon-area AREA"
  echo "using numbers from your synthesis/FPGA implementation reports."
fi
