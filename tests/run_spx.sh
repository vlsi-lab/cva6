#!/bin/bash
# =============================================================================
# tests/run_spx.sh - Interactive picker for SLH-DSA SPHINCS+ variants
#
# This script lets users choose between baseline and optimized versions
# of SPHINCS+ (128f, 192f, 256f) in both robust and simple modes.
#
# Usage (from the cva6 repo root, either way works):
#     bash   tests/run_spx.sh        # spawns a child shell
#     source tests/run_spx.sh        # runs in the current shell
#
# All errors only stop *this* script — they never close the calling shell.
# =============================================================================

# _rt_die <msg>: report and stop the script (works whether sourced or not).
_rt_die() {
    echo "Error: $*" >&2
    return 1 2>/dev/null || exit 1
}

THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
if [ -z "$THIS_DIR" ]; then
    _rt_die "could not resolve script directory"
    return 1 2>/dev/null || exit 1
fi

# Collect all SLH-DSA run.sh scripts (both baseline and optimized)
mapfile -t SCRIPTS < <(find "$THIS_DIR/pqc/baseline/DS/SLH-DSA" "$THIS_DIR/pqc/optimized/DS/SLH-DSA" \
                            -mindepth 2 -maxdepth 2 -name 'run.sh' \
                            -printf '%h/run.sh\n' 2>/dev/null | sort)

if (( ${#SCRIPTS[@]} == 0 )); then
    _rt_die "no per-test run.sh scripts found under $THIS_DIR/pqc/{baseline,optimized}/DS/SLH-DSA/*"
    return 1 2>/dev/null || exit 1
fi

echo
echo "╔════════════════════════════════════════════════════════╗"
echo "║          SLH-DSA SPHINCS+ Test Selector              ║"
echo "║                                                        ║"
echo "║ Choose a variant and optimization mode to test:       ║"
echo "╚════════════════════════════════════════════════════════╝"
echo

# Display options with nice formatting
for i in "${!SCRIPTS[@]}"; do
    dir=$(dirname "${SCRIPTS[$i]}")
    variant=$(basename "$dir")
    
    # Determine if baseline or optimized
    if [[ "$dir" == */baseline/* ]]; then
        mode="[BASELINE]"
    else
        mode="[OPTIMIZED]"
    fi
    
    printf "  [%2d] %-50s %s\n" "$i" "$variant" "$mode"
done

echo
if ! read -rp "Select a test (number): " IDX; then
    _rt_die "no input received"
    return 1 2>/dev/null || exit 1
fi

if ! [[ "$IDX" =~ ^[0-9]+$ ]] || (( IDX < 0 || IDX >= ${#SCRIPTS[@]} )); then
    _rt_die "invalid selection: '$IDX'"
    return 1 2>/dev/null || exit 1
fi

# Get the selected script and run it
selected_script="${SCRIPTS[$IDX]}"
selected_dir=$(dirname "$selected_script")
selected_name=$(basename "$selected_dir")

echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Running: $selected_name"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo

# Execute the selected test
bash "$selected_script"
RC=$?

if (( RC == 0 )); then
    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "✓ Test passed: $selected_name"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
else
    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "✗ Test failed: $selected_name (exit code: $RC)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
fi

return "$RC" 2>/dev/null || exit "$RC"
