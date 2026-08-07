#!/bin/bash
# Aggregate test runner across all three implementations of the kecc-aes-k
# algorithms (pure software / ISE coprocessor / loosely-coupled AXI
# accelerator), composing the three existing per-tree dispatchers
# (tests/software/run.sh, tests/tightly/run.sh, tests/loosely/run.sh) instead
# of reimplementing test discovery or the cva6.py invocation.
#
# Usage (run from the cva6 repo root):
#   tests/run_all.sh [WHICH] [TEST] [REPEAT_N]
#
#   WHICH:     sw | ise | loose_v2 | all   (default: all)
#              loose_v3/loose_v4_*/loose_v5_* will work once those variants
#              are vendored and added to scripts/select_aes_variant.sh.
#   TEST:      a test name (must exist in every tree WHICH touches) or 'all'
#              (default: all)
#   REPEAT_N:  how many times to repeat the whole selection (default: 1) --
#              this is the "repeat hundreds of times" knob; each repetition
#              re-invokes cva6.py from scratch (a fresh Verilator run), so
#              large REPEAT_N values are slow by nature of full-chip RTL sim,
#              not a limitation of this script.
#
# Examples:
#   tests/run_all.sh sw aes_core 1
#   tests/run_all.sh loose_v2 all 5
#   tests/run_all.sh all keccak_core 10
#
# Correctness comes from each test's own printed "terminated with no errors"
# / "!!! ... mismatch !!!" line (cva6.py's own exit code does not reflect
# RTL/expected-value mismatches, see verif/sim/cva6.py:668) -- this script
# greps that line out of each run's captured output so REPEAT_N runs don't
# require manually re-reading logs.

set -u

WHICH="${1:-all}"
TEST="${2:-all}"
REPEAT_N="${3:-1}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

LOG_DIR="$ROOT_DIR/tests/run_all_logs/$(date +%Y%m%d_%H%M%S)"
mkdir -p "$LOG_DIR"

declare -a VARIANTS
case "$WHICH" in
    all)          VARIANTS=(sw ise loose_v2) ;;
    sw|ise)       VARIANTS=("$WHICH") ;;
    loose_*)      VARIANTS=("$WHICH") ;;
    *)            echo "Unknown WHICH '$WHICH' (expected sw|ise|loose_v2|...|all)" >&2; exit 1 ;;
esac

run_tree() {
    local variant="$1" test="$2" iter="$3"
    local tree run_cmd logfile
    case "$variant" in
        sw)   tree="tests/software" ;;
        ise)  tree="tests/tightly" ;;
        loose_*) tree="tests/loosely" ;;
    esac

    logfile="$LOG_DIR/${variant}_${test}_iter${iter}.log"

    if [ "$variant" = "sw" ] || [ "$variant" = "ise" ]; then
        ( bash "$tree/run.sh" "$test" ) >"$logfile" 2>&1
    else
        ( export AES_VARIANT="$variant"; bash "$tree/run.sh" "$test" ) >"$logfile" 2>&1
    fi
    local rc=$?

    # The actual "terminated with no errors" / "!!! Mismatch !!!" line comes from
    # the simulated UART, which cva6.py writes to a separate
    # verif/sim/out_*/veri-testharness_sim/<test>.<cva6-target>.log.iss file, not
    # to its own stdout (what $logfile captures) -- check both, newest .log.iss
    # matching this test name first since that's where the real signal lives.
    local iss_log
    iss_log=$(ls -t "$ROOT_DIR"/verif/sim/out_*/veri-testharness_sim/"${test}".*.log.iss 2>/dev/null | head -1)

    local status
    if grep -q "!!! .*[Mm]ismatch.*!!!" "$logfile" "$iss_log" 2>/dev/null; then
        status="MISMATCH"
    elif grep -q "terminated with no errors" "$logfile" "$iss_log" 2>/dev/null; then
        status="PASS"
    elif [ $rc -ne 0 ]; then
        status="RUN_FAILED"
    else
        status="UNKNOWN"
    fi

    printf "%-10s %-20s iter=%-4s %-10s log=%s\n" "$variant" "$test" "$iter" "$status" "$logfile" >&2
    echo "$status"
}

declare -A TALLY

for variant in "${VARIANTS[@]}"; do
    case "$variant" in
        sw)   TREE_DIR="tests/software" ;;
        ise)  TREE_DIR="tests/tightly" ;;
        *)    TREE_DIR="tests/loosely" ;;
    esac

    if [ "$TEST" = "all" ]; then
        mapfile -t TESTS_TO_RUN < <(find "$TREE_DIR" -mindepth 1 -maxdepth 1 -type d ! -name common -exec basename {} \; | sort)
    else
        TESTS_TO_RUN=("$TEST")
    fi

    for t in "${TESTS_TO_RUN[@]}"; do
        for ((i = 1; i <= REPEAT_N; i++)); do
            status=$(run_tree "$variant" "$t" "$i" | tail -1)
            key="${variant}:${t}:${status}"
            TALLY["$key"]=$(( ${TALLY["$key"]:-0} + 1 ))
        done
    done
done

echo ""
echo "=== Summary (logs under $LOG_DIR) ==="
for key in "${!TALLY[@]}"; do
    echo "$key -> ${TALLY[$key]}"
done | sort
