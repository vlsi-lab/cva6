#!/bin/bash
# ****************************************************************************
#
# Desc: Unified launcher for the verify-only PQC tests under tests/vrf/.
#       vrf_ip is a verify-only accelerator, so every variant here exercises
#       only crypto_sign_open()/crypto_sign_verify() -- keygen/sign are not
#       run (see tests/pqc/ for the full keygen+sign+verify harness).
#       Dispatches to the per-variant run.sh scripts (tests/vrf/{baseline,
#       optimized}/<variant>/run.sh), each of which builds and runs a single
#       scheme's KAT + cycle/instruction-profiling verify test on the CVA6
#       simulator. See the corresponding variant's run.sh for build/source
#       details.
#
# Usage:
#   ./tests/vrf/run.sh                    - interactive menu
#   ./tests/vrf/run.sh <variant>
#   ./tests/vrf/run.sh all                - run every variant, one after another
#
#   <variant> is one of:
#       baseline-falcon512          optimized-falcon512
#       baseline-falcon1024         optimized-falcon1024
#       baseline-ML-DSA-44          optimized-ML-DSA-44
#       baseline-ML-DSA-65          optimized-ML-DSA-65
#       baseline-ML-DSA-87          optimized-ML-DSA-87
#       baseline-SPHINCS-128f-robust    optimized-SPHINCS-128f-robust
#       baseline-SPHINCS-128f-simple    optimized-SPHINCS-128f-simple
#       baseline-SPHINCS-192f-robust    optimized-SPHINCS-192f-robust
#       baseline-SPHINCS-192f-simple    optimized-SPHINCS-192f-simple
#       baseline-SPHINCS-256f-robust    optimized-SPHINCS-256f-robust
#       baseline-SPHINCS-256f-simple    optimized-SPHINCS-256f-simple
#
# May be invoked from anywhere; it locates the CVA6 repository root itself.
#
# ****************************************************************************

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

ORDER=(
    baseline-falcon512               optimized-falcon512
    baseline-falcon1024               optimized-falcon1024
    baseline-ML-DSA-44                optimized-ML-DSA-44
    baseline-ML-DSA-65                optimized-ML-DSA-65
    baseline-ML-DSA-87                optimized-ML-DSA-87
    baseline-SPHINCS-128f-robust      optimized-SPHINCS-128f-robust
    baseline-SPHINCS-128f-simple      optimized-SPHINCS-128f-simple
    baseline-SPHINCS-192f-robust      optimized-SPHINCS-192f-robust
    baseline-SPHINCS-192f-simple      optimized-SPHINCS-192f-simple
    baseline-SPHINCS-256f-robust      optimized-SPHINCS-256f-robust
    baseline-SPHINCS-256f-simple      optimized-SPHINCS-256f-simple
)

variant_path() {
    local name="$1" kind variant
    kind="${name%%-*}"
    variant="${name#*-}"
    echo "tests/vrf/$kind/$variant/run.sh"
}

usage() {
    echo "Usage: $0 [<variant>|all]" >&2
    echo "  <variant> is one of: ${ORDER[*]}" >&2
    exit 1
}

run_variant() {
    local name="$1" script
    script="$(variant_path "$name")"
    echo ""
    echo "==> Running $name =========================================="
    ( cd "$REPO_ROOT" && bash "$script" )
}

VARIANT="$1"

if [[ -z "$VARIANT" ]]; then
    echo "Available verify-only PQC tests:"
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
fi

if [[ "$VARIANT" == "all" ]]; then
    for name in "${ORDER[@]}"; do
        run_variant "$name"
    done
else
    found=0
    for name in "${ORDER[@]}"; do
        [[ "$name" == "$VARIANT" ]] && found=1
    done
    if [[ "$found" == "1" ]]; then
        run_variant "$VARIANT"
    else
        usage
    fi
fi
