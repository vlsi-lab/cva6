#!/bin/bash
# Dispatcher for the tests/tightly/ benchmark suite (coprocessor-accelerated (kecc_aes_k_xif) variant;
# see tests/software/run.sh for the pure-software baseline counterparts).
#
# Usage (run from the cva6 repo root):
#   source tests/tightly/run.sh              # interactive menu
#   source tests/tightly/run.sh <test_name>  # run just that test
#   source tests/tightly/run.sh all          # run every test, print a summary

TREE_DIR="./tests/tightly"

mapfile -t TESTS < <(find "$TREE_DIR" -mindepth 1 -maxdepth 1 -type d ! -name common -exec basename {} \; | sort)

if (( ${#TESTS[@]} == 0 )); then
    echo "No tests found in $TREE_DIR"
    return 1 2>/dev/null || exit 1
fi

run_one() {
    local name="$1"
    echo ""
    echo "=== Running $name ==="
    bash "$TREE_DIR/$name/run.sh"
    return $?
}

SELECTED="$1"

if [ -z "$SELECTED" ]; then
    echo "Available tightly tests:"
    for i in "${!TESTS[@]}"; do
        echo "[$i] ${TESTS[$i]}"
    done
    echo "[all] run every test"
    echo ""
    read -p "Select a test (number or 'all'): " SELECTED
fi

if [ "$SELECTED" = "all" ]; then
    RUN_FAIL_COUNT=0
    for name in "${TESTS[@]}"; do
        run_one "$name"
        if [ $? -ne 0 ]; then
            RUN_FAIL_COUNT=$((RUN_FAIL_COUNT + 1))
        fi
    done
    echo ""
    echo "=== tightly suite: ran ${#TESTS[@]} tests, $RUN_FAIL_COUNT failed to compile/run ==="
    echo "Note: this only reflects compile/simulation-run failures. cva6.py itself does not"
    echo "fail its exit code on RTL/expected-value mismatches (see the comment at"
    echo "verif/sim/cva6.py:668) -- check each test's own 'no errors' / '!!! mismatch !!!'"
    echo "line above (or its log under verif/sim/out_*/veri-testharness_sim/) for the"
    echo "actual correctness result."
elif [[ "$SELECTED" =~ ^[0-9]+$ ]]; then
    run_one "${TESTS[$SELECTED]}"
else
    if [ -d "$TREE_DIR/$SELECTED" ]; then
        run_one "$SELECTED"
    else
        echo "Unknown test: $SELECTED"
        echo "Available: ${TESTS[*]} all"
        return 1 2>/dev/null || exit 1
    fi
fi
