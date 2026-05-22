#!/bin/bash
# =============================================================================
# tests/run_spx_cw305.sh - Interactive picker for SLH-DSA SPHINCS+ variants,
# built with CW305-style compilation flags.
#
# This is a thin wrapper around tests/run_spx_batch_cw305.sh that asks for a
# single (mode/variant/phase) combination and runs just that one simulation.
#
# Usage (from anywhere):
#     bash   tests/run_spx_cw305.sh        # spawns a child shell
#     source tests/run_spx_cw305.sh        # runs in the current shell
# =============================================================================

_rt_die() {
    echo "Error: $*" >&2
    return 1 2>/dev/null || exit 1
}

THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
[ -n "$THIS_DIR" ] || { _rt_die "could not resolve script directory"; return 1 2>/dev/null || exit 1; }

BATCH="$THIS_DIR/run_spx_batch_cw305.sh"
[ -f "$BATCH" ] || { _rt_die "missing $BATCH"; return 1 2>/dev/null || exit 1; }

# Collect all SLH-DSA variant directories (mode/variant pairs that have run.sh)
mapfile -t SCRIPTS < <(find "$THIS_DIR/pqc/baseline/DS/SLH-DSA" "$THIS_DIR/pqc/optimized/DS/SLH-DSA" \
                            -mindepth 2 -maxdepth 2 -name 'run.sh' \
                            -printf '%h/run.sh\n' 2>/dev/null | sort)

if (( ${#SCRIPTS[@]} == 0 )); then
    _rt_die "no per-test run.sh scripts found under $THIS_DIR/pqc/{baseline,optimized}/DS/SLH-DSA/*"
    return 1 2>/dev/null || exit 1
fi

echo
echo "╔════════════════════════════════════════════════════════╗"
echo "║    SLH-DSA SPHINCS+ Selector  [CW305 build flags]    ║"
echo "╚════════════════════════════════════════════════════════╝"
echo

for i in "${!SCRIPTS[@]}"; do
    dir=$(dirname "${SCRIPTS[$i]}")
    variant=$(basename "$dir")
    if [[ "$dir" == */baseline/* ]]; then mode="[BASELINE]"; else mode="[OPTIMIZED]"; fi
    printf "  [%2d] %-50s %s\n" "$i" "$variant" "$mode"
done

echo
if ! read -rp "Select a variant (number): " IDX; then
    _rt_die "no input received"
    return 1 2>/dev/null || exit 1
fi
if ! [[ "$IDX" =~ ^[0-9]+$ ]] || (( IDX < 0 || IDX >= ${#SCRIPTS[@]} )); then
    _rt_die "invalid selection: '$IDX'"
    return 1 2>/dev/null || exit 1
fi

selected_dir=$(dirname "${SCRIPTS[$IDX]}")
selected_variant=$(basename "$selected_dir")
if [[ "$selected_dir" == */baseline/* ]]; then selected_mode="baseline"
else                                            selected_mode="optimized"
fi

echo
echo "Phases:"
echo "  [1] keygen"
echo "  [2] sign"
echo "  [3] verify"
echo "  [4] all (keygen+sign+verify)"
if ! read -rp "Select a phase (1-4): " PHASE_IDX; then
    _rt_die "no input received"
    return 1 2>/dev/null || exit 1
fi
case "$PHASE_IDX" in
    1) phases=(keygen) ;;
    2) phases=(sign) ;;
    3) phases=(verify) ;;
    4) phases=(keygen sign verify) ;;
    *) _rt_die "invalid phase: '$PHASE_IDX'"; return 1 2>/dev/null || exit 1 ;;
esac

echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Running (CW305 build): $selected_mode / $selected_variant / ${phases[*]}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo

bash "$BATCH" --mode "$selected_mode" --variants "$selected_variant" "${phases[@]}"
RC=$?

if (( RC == 0 )); then
    echo "✓ Done: $selected_mode / $selected_variant / ${phases[*]}"
else
    echo "✗ Failed (exit $RC): $selected_mode / $selected_variant / ${phases[*]}"
fi

return "$RC" 2>/dev/null || exit "$RC"
