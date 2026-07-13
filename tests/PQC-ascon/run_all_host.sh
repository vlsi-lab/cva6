#!/bin/bash
#
# Batch-builds and runs every PQC-ascon variant's host Makefile (native gcc,
# PERF_CNT_CYCLES disabled) back to back, and prints a summary table at the
# end. This is the fast pre-simulation sanity check -- see run_all.sh for
# the RISC-V/RTL simulator equivalent (much slower, needs $RISCV etc. set).
#
# Usage:
#   tests/PQC-ascon/run_all_host.sh [--variants v1,v2,...]
#
# Examples:
#   tests/PQC-ascon/run_all_host.sh                       # all 6 variants
#   tests/PQC-ascon/run_all_host.sh --variants ML-DSA-2,ml-kem-512
#
# Run this with `bash`, not `source`/`.` -- it uses `set -u` and `exit`,
# which would otherwise leak nounset into your interactive shell and/or
# close your terminal on an error path.

if (return 0 2>/dev/null); then
  echo "Run this with bash, not 'source': bash ${BASH_SOURCE[0]} $*" >&2
  return 1
fi

set -u

ALL_VARIANTS=(ML-DSA-2 ML-DSA-3 ML-DSA-5 ml-kem-512 ml-kem-768 ml-kem-1024)
VARIANTS=("${ALL_VARIANTS[@]}")

while [[ $# -gt 0 ]]; do
  case "$1" in
    --variants)
      IFS=',' read -r -a VARIANTS <<< "$2"; shift 2 ;;
    -h|--help)
      sed -n '2,10p' "$0"; exit 0 ;;
    *)
      echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT/tests/PQC-ascon" || exit 1

TS="$(date +%Y%m%d_%H%M%S)"
RESULTS_DIR="$REPO_ROOT/tests/PQC-ascon/bench_results_host/$TS"
mkdir -p "$RESULTS_DIR"

echo "Results and full logs: $RESULTS_DIR"
echo "Variants: ${VARIANTS[*]}"
echo

# name|status|elapsed
declare -a SUMMARY

for variant in "${VARIANTS[@]}"; do
  dir="$variant"
  if [ ! -f "$dir/Makefile" ]; then
    echo ">>> SKIP $variant: $dir/Makefile not found" >&2
    SUMMARY+=("$variant|MISSING|")
    continue
  fi

  logfile="$RESULTS_DIR/${variant}.log"

  echo "=== [$variant] starting ($(date +%H:%M:%S)) ==="
  start=$(date +%s)
  ( cd "$dir" && make clean && make run ) > "$logfile" 2>&1
  rc=$?
  end=$(date +%s)
  elapsed=$((end - start))

  if grep -q "Test Successful" "$logfile"; then
    status="PASS"
  elif grep -q "Test FAILED" "$logfile"; then
    status="FAIL (mismatch)"
  elif [ "$rc" -ne 0 ]; then
    status="ERROR (build, rc=$rc)"
  else
    status="UNKNOWN (no Test Successful/FAILED marker)"
  fi

  echo "=== [$variant] $status  (${elapsed}s)  -> $logfile ==="
  echo

  SUMMARY+=("$variant|$status|${elapsed}s")

  # Host binaries are throwaway sanity-check artifacts, not meant to linger.
  ( cd "$dir" && make clean ) > /dev/null 2>&1
done

echo
echo "==================== SUMMARY ===================="
printf "%-12s %-28s %s\n" "VARIANT" "STATUS" "TIME"
printf '%s\n' "--------------------------------------------------------"
for row in "${SUMMARY[@]}"; do
  IFS='|' read -r v s t <<< "$row"
  printf "%-12s %-28s %s\n" "$v" "$s" "$t"
done
echo "==================================================="
echo "Full logs in: $RESULTS_DIR"
