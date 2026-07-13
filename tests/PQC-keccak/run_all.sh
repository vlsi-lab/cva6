#!/bin/bash
#
# Batch-runs every PQC-keccak variant's run.sh (software-only and/or AXI
# coprocessor build) back to back on the cva6 RTL simulator, and prints a
# summary table of pass/fail + per-phase cycle counts at the end.
#
# Usage:
#   tests/PQC-keccak/run_all.sh [--only sw|hw|both] [--variants v1,v2,...] [--timeout SECONDS]
#
# Examples:
#   tests/PQC-keccak/run_all.sh                       # all 6 variants, sw + hw
#   tests/PQC-keccak/run_all.sh --only hw             # AXI-accelerated builds only
#   tests/PQC-keccak/run_all.sh --variants ML-DSA-2,ml-kem-512
#   tests/PQC-keccak/run_all.sh --timeout 900         # kill any single run after 15 min

set -u

ALL_VARIANTS=(ML-DSA-2 ML-DSA-3 ML-DSA-5 ml-kem-512 ml-kem-768 ml-kem-1024)
ONLY="both"
TIMEOUT=1800
VARIANTS=("${ALL_VARIANTS[@]}")

while [[ $# -gt 0 ]]; do
  case "$1" in
    --only)
      ONLY="$2"; shift 2 ;;
    --variants)
      IFS=',' read -r -a VARIANTS <<< "$2"; shift 2 ;;
    --timeout)
      TIMEOUT="$2"; shift 2 ;;
    -h|--help)
      sed -n '2,15p' "$0"; exit 0 ;;
    *)
      echo "Unknown option: $1" >&2; exit 1 ;;
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
RESULTS_DIR="$REPO_ROOT/tests/PQC-keccak/bench_results/$TS"
mkdir -p "$RESULTS_DIR"

echo "Results and full logs: $RESULTS_DIR"
echo "Variants: ${VARIANTS[*]}"
echo "Modes: ${MODES[*]:-sw}"
echo "Per-run timeout: ${TIMEOUT}s"
echo

# name|mode|status|extra_cycle_lines
declare -a SUMMARY

for variant in "${VARIANTS[@]}"; do
  run_sh="tests/PQC-keccak/$variant/run.sh"
  if [ ! -f "$run_sh" ]; then
    echo ">>> SKIP $variant: $run_sh not found" >&2
    SUMMARY+=("$variant|-|MISSING|")
    continue
  fi

  for mode in "${MODES[@]}"; do
    label="sw"; [[ "$mode" == "copro" ]] && label="hw"
    logfile="$RESULTS_DIR/${variant}_${label}.log"

    # cva6.py redirects the *target's* own stdout (the printf/UART output we
    # actually care about) into <output_dir>/veri-testharness_sim/main.<target>.log.iss
    # rather than its own stdout. By default <output_dir> is the fixed,
    # date-named out_<date>/ -- shared by every variant AND by anything the
    # user runs manually in another terminal at the same time -- so
    # concurrent runs clobber/interleave each other's log. Force cva6.py's
    # "-o <dir>" (forwarded through $DV_OPTS, which every run.sh appends its
    # own opts to) so each run here gets its own private output directory.
    dv_target="$(grep -oP '(?<=^DV_TARGET=)\S+' "$run_sh")"
    run_out_dir="$RESULTS_DIR/${variant}_${label}_simout"
    iss_log="$run_out_dir/veri-testharness_sim/main.${dv_target}.log.iss"

    echo "=== [$variant / $label] starting ($(date +%H:%M:%S)) ==="
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

    cycles="$(grep -oE 'cycles [A-Za-z0-9_]+: [0-9]+' "$logfile" | tr '\n' ';' | sed 's/;$//')"

    echo "=== [$variant / $label] $status  (${elapsed}s)  -> $logfile ==="
    echo

    SUMMARY+=("$variant|$label|$status ($((elapsed))s)|$cycles")
  done
done

echo
echo "==================== SUMMARY ===================="
printf "%-12s %-4s %-28s %s\n" "VARIANT" "MODE" "STATUS" "CYCLES"
printf '%s\n' "----------------------------------------------------------------------------------------"
for row in "${SUMMARY[@]}"; do
  IFS='|' read -r v m s c <<< "$row"
  printf "%-12s %-4s %-28s %s\n" "$v" "$m" "$s" "$c"
done
echo "==================================================="
echo "Full logs in: $RESULTS_DIR"
