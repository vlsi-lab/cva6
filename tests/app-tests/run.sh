#!/bin/bash
# ****************************************************************************
#
# Desc: Unified launcher for the digsig primitive-level app-tests under
#       tests/app-tests/. Each test builds and simulates a small standalone
#       SW-vs-HW comparison (software reference vs. the digsig accelerator
#       IP) on the CVA6 Verilator model, printing PASS/FAIL, SW cycles, HW
#       cycles, and speedup. This script dispatches to each test's own
#       run.sh, then prints a single pass/cycle/speedup summary table.
#
# Usage:
#   ./tests/app-tests/run.sh                 - interactive menu
#   ./tests/app-tests/run.sh <test>           - run a single test
#   ./tests/app-tests/run.sh all              - run every test, print summary
#   ./tests/app-tests/run.sh --list           - list available test names
#
#   TEST_TIMEOUT=<seconds>  - per-test wall-clock timeout (default: 180).
#                              thash/thash2/thash-wots/prf-addr are known to
#                              hang indefinitely (see CHAIN_TOP_AXI_BUG.md at
#                              the repo root) and will report TIMEOUT unless
#                              given a much larger budget.
#
# May be invoked from anywhere; it locates the CVA6 repository root itself.
#
# ****************************************************************************

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TEST_TIMEOUT="${TEST_TIMEOUT:-180}"

# Order matters only for display; keeps the NTT/Keccak-primitive tests (which
# wrap the proven-working vrf_ip) ahead of the chain_top-based SPHINCS+
# tests (which hit the open bug documented in CHAIN_TOP_AXI_BUG.md).
ORDER=(
    ntt
    intt
    keccak-permute
    keccak-abs-shake256
    keccak-abs-sha3-256-single-block
    keccak-abs-sha3-256-multi-block
    keccak-abs-multi-squeeze
    thash
    thash2
    thash-wots
    prf-addr
)

declare -A KNOWN_ISSUE=(
    [thash]=1 [thash2]=1 [thash-wots]=1 [prf-addr]=1
)

usage() {
    local names
    names=$(IFS='|'; echo "${ORDER[*]}")
    echo "Usage: $0 [${names}|all]" >&2
    exit 1
}

# Locate the newest simulation transcript produced by the run we just did.
find_latest_log() {
    find "$REPO_ROOT/verif/sim" -path '*/veri-testharness_sim/*.log.iss' -newer "$1" -print 2>/dev/null \
        | xargs -r ls -t 2>/dev/null | head -1
}

# Populates globals: RESULT_STATUS RESULT_SW RESULT_HW RESULT_SPEEDUP
parse_log() {
    local log="$1"
    RESULT_SW="-"; RESULT_HW="-"; RESULT_SPEEDUP="-"

    if [[ -z "$log" || ! -f "$log" ]]; then
        RESULT_STATUS="NO LOG"
        return
    fi

    if grep -q "FAIL\]\|FINAL STATUS:.*FAILED" "$log" 2>/dev/null; then
        RESULT_STATUS="FAIL"
    elif grep -q "PASS\]\|FINAL STATUS: ALL TESTS PASSED" "$log" 2>/dev/null; then
        RESULT_STATUS="PASS"
    elif grep -q "FAILED \*\*\*" "$log" 2>/dev/null; then
        RESULT_STATUS="HANG/FAIL"
    else
        RESULT_STATUS="UNKNOWN"
    fi

    local sw hw
    sw=$(grep -oE "SW cycles: [0-9]+" "$log" 2>/dev/null | tail -1 | grep -oE "[0-9]+")
    hw=$(grep -oE "HW cycles: [0-9]+" "$log" 2>/dev/null | tail -1 | grep -oE "[0-9]+")
    [[ -n "$sw" ]] && RESULT_SW="$sw"
    [[ -n "$hw" ]] && RESULT_HW="$hw"

    if [[ -n "$sw" && -n "$hw" && "$hw" -gt 0 ]]; then
        RESULT_SPEEDUP=$(awk -v s="$sw" -v h="$hw" 'BEGIN{printf "%.2fx", s/h}')
    fi
}

run_test() {
    local name="$1"
    local script="$REPO_ROOT/tests/app-tests/$name/run.sh"
    local marker
    marker="$(mktemp)"

    echo ""
    echo "==> Running $name ($TEST_TIMEOUT s budget) =========================================="
    if [[ -n "${KNOWN_ISSUE[$name]:-}" ]]; then
        echo "    NOTE: known open issue, see CHAIN_TOP_AXI_BUG.md at the repo root."
    fi

    if timeout "$TEST_TIMEOUT" bash "$script"; then
        :
    else
        local rc=$?
        if [[ $rc -eq 124 ]]; then
            RESULT_STATUS="TIMEOUT"; RESULT_SW="-"; RESULT_HW="-"; RESULT_SPEEDUP="-"
            SUMMARY_NAME+=("$name"); SUMMARY_STATUS+=("$RESULT_STATUS")
            SUMMARY_SW+=("$RESULT_SW"); SUMMARY_HW+=("$RESULT_HW"); SUMMARY_SPEEDUP+=("$RESULT_SPEEDUP")
            rm -f "$marker"
            return
        fi
    fi

    local log
    log="$(find_latest_log "$marker")"
    parse_log "$log"
    SUMMARY_NAME+=("$name"); SUMMARY_STATUS+=("$RESULT_STATUS")
    SUMMARY_SW+=("$RESULT_SW"); SUMMARY_HW+=("$RESULT_HW"); SUMMARY_SPEEDUP+=("$RESULT_SPEEDUP")
    rm -f "$marker"
}

print_summary() {
    echo ""
    echo "==================================================================================="
    echo " Summary"
    echo "==================================================================================="
    printf "%-34s %-10s %14s %14s %10s\n" "Test" "Status" "SW cycles" "HW cycles" "Speedup"
    printf "%-34s %-10s %14s %14s %10s\n" "----" "------" "---------" "---------" "-------"
    for i in "${!SUMMARY_NAME[@]}"; do
        printf "%-34s %-10s %14s %14s %10s\n" \
            "${SUMMARY_NAME[$i]}" "${SUMMARY_STATUS[$i]}" "${SUMMARY_SW[$i]}" "${SUMMARY_HW[$i]}" "${SUMMARY_SPEEDUP[$i]}"
    done
    echo "==================================================================================="
    echo " TIMEOUT/HANG/FAIL entries for thash/thash2/thash-wots/prf-addr are the known open"
    echo " issue documented in CHAIN_TOP_AXI_BUG.md (repo root) -- not a new regression."
    echo "==================================================================================="
}

SUMMARY_NAME=(); SUMMARY_STATUS=(); SUMMARY_SW=(); SUMMARY_HW=(); SUMMARY_SPEEDUP=()

TARGET="$1"

if [[ "$TARGET" == "--list" ]]; then
    printf '%s\n' "${ORDER[@]}"
    exit 0
fi

if [[ -z "$TARGET" ]]; then
    echo "Available app-tests:"
    for i in "${!ORDER[@]}"; do
        note=""
        [[ -n "${KNOWN_ISSUE[${ORDER[$i]}]:-}" ]] && note="  (known open issue)"
        echo "  [$i] ${ORDER[$i]}$note"
    done
    echo "  [a] all"
    echo ""
    read -p "Select a test: " CHOICE
    if [[ "$CHOICE" == "a" ]]; then
        TARGET="all"
    elif [[ "$CHOICE" =~ ^[0-9]+$ && -n "${ORDER[$CHOICE]:-}" ]]; then
        TARGET="${ORDER[$CHOICE]}"
    else
        echo "Invalid selection." >&2
        exit 1
    fi
fi

case "$TARGET" in
    all)
        for name in "${ORDER[@]}"; do
            run_test "$name"
        done
        print_summary
        ;;
    *)
        found=0
        for name in "${ORDER[@]}"; do
            [[ "$name" == "$TARGET" ]] && found=1
        done
        if [[ $found -eq 0 ]]; then
            usage
        fi
        run_test "$TARGET"
        print_summary
        ;;
esac
