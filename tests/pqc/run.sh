#!/bin/bash
# ****************************************************************************
#
# Desc: Unified launcher for the Falcon PQC tests under tests/pqc/. Dispatches
#       to the per-variant run.sh scripts (tests/pqc/{baseline,optimized}/
#       falcon{512,1024}/run.sh), each of which builds and runs a single
#       Falcon variant's KAT + cycle-profiling test on the CVA6 simulator.
#       See the corresponding variant's run.sh for build/source details.
#
# Usage:
#   ./tests/pqc/run.sh                                 - interactive menu
#   ./tests/pqc/run.sh <variant> [keygen|sign|verify|all]
#   ./tests/pqc/run.sh all [keygen|sign|verify|all]     - run every variant,
#                                                          one after another
#
#   <variant> is one of:
#       baseline-falcon512    baseline-falcon1024
#       optimized-falcon512   optimized-falcon1024
#
#   [keygen|sign|verify|all] is forwarded as-is to the variant's run.sh
#   (default: all).
#
# May be invoked from anywhere; it locates the CVA6 repository root itself.
#
# ****************************************************************************

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

declare -A VARIANTS=(
    [baseline-falcon512]="tests/pqc/baseline/falcon512/run.sh"
    [baseline-falcon1024]="tests/pqc/baseline/falcon1024/run.sh"
    [optimized-falcon512]="tests/pqc/optimized/falcon512/run.sh"
    [optimized-falcon1024]="tests/pqc/optimized/falcon1024/run.sh"
)
ORDER=(baseline-falcon512 baseline-falcon1024 optimized-falcon512 optimized-falcon1024)

PHASE_RE='^(keygen|sign|verify|all)$'

usage() {
    local names
    names=$(IFS='|'; echo "${ORDER[*]}")
    echo "Usage: $0 [${names}|all] [keygen|sign|verify|all]" >&2
    exit 1
}

run_variant() {
    local name="$1" phase="$2"
    echo ""
    echo "==> Running $name (${phase}) =========================================="
    ( cd "$REPO_ROOT" && bash "${VARIANTS[$name]}" "$phase" )
}

VARIANT="$1"
PHASE="${2:-all}"

if [[ -z "$VARIANT" ]]; then
    echo "Available Falcon tests:"
    for i in "${!ORDER[@]}"; do
        echo "  [$i] ${ORDER[$i]}"
    done
    echo "  [a] all"
    echo ""
    read -p "Select a test: " CHOICE
    if [[ "$CHOICE" == "a" ]]; then
        VARIANT="all"
    elif [[ "$CHOICE" =~ ^[0-9]+$ && -n "${ORDER[$CHOICE]:-}" ]]; then
        VARIANT="${ORDER[$CHOICE]}"
    else
        echo "Invalid selection." >&2
        exit 1
    fi
    read -p "Phase [keygen|sign|verify|all] (default: all): " PHASE_IN
    PHASE="${PHASE_IN:-all}"
fi

if [[ ! "$PHASE" =~ $PHASE_RE ]]; then
    usage
fi

if [[ "$VARIANT" == "all" ]]; then
    for name in "${ORDER[@]}"; do
        run_variant "$name" "$PHASE"
    done
elif [[ -n "${VARIANTS[$VARIANT]+_}" ]]; then
    run_variant "$VARIANT" "$PHASE"
else
    usage
fi
