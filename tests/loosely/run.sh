#!/bin/bash
# Dispatcher for the tests/loosely/ benchmark suite (loosely-coupled AXI accelerator
# (kecc_aes_k_axi) variant; see tests/software/run.sh for the pure-software baseline
# and tests/tightly/run.sh for the ISE/coprocessor variant).
#
# Which kecc_aes_k_axi RTL variant/target gets built is controlled by AES_VARIANT
# (default loose_v2, the only variant vendored so far -- see
# scripts/select_aes_variant.sh), forwarded to each test's own run.sh.
#
# Usage (run from the cva6 repo root):
#   source tests/loosely/run.sh              # interactive menu
#   source tests/loosely/run.sh <test_name>  # run just that test
#   source tests/loosely/run.sh all          # run every test, print a summary

TREE_DIR="./tests/loosely"
export AES_VARIANT=${AES_VARIANT:-loose_v2}

mapfile -t TESTS < <(find "$TREE_DIR" -mindepth 1 -maxdepth 1 -type d ! -name common -exec basename {} \; | sort)

if (( ${#TESTS[@]} == 0 )); then
    echo "No tests found in $TREE_DIR"
    return 1 2>/dev/null || exit 1
fi

run_one() {
    local name="$1"
    echo ""
    echo "=== Running $name (AES_VARIANT=$AES_VARIANT) ==="
    bash "$TREE_DIR/$name/run.sh"
    return $?
}

SELECTED="$1"

if [ -z "$SELECTED" ]; then
    echo "Available loosely tests (AES_VARIANT=$AES_VARIANT):"
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
    echo "=== loosely suite (AES_VARIANT=$AES_VARIANT): ran ${#TESTS[@]} tests, $RUN_FAIL_COUNT failed to compile/run ==="
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
    fi
fi
