#!/bin/bash
# =============================================================================
# tests/run_tests_cw305.sh - Interactive picker for HASH coprocessor tests,
# built with CW305-style compilation flags (rv64imac/lp64, -Os, cw305 runtime).
#
# Currently only the SLH-DSA SPHINCS+ variants under
#   tests/pqc/{baseline,optimized}/DS/SLH-DSA/<variant>/
# are supported under the CW305 build, because cw305_crt.S /
# cw305_linker.ld are tailored to those tests.  Selecting a non-SPHINCS test
# will fall back to that test's own run.sh (i.e. the *non*-CW305 default
# flags) with a clear warning.
#
# Usage (from the cva6 repo root, either way works):
#     bash   tests/run_tests_cw305.sh        # spawns a child shell
#     source tests/run_tests_cw305.sh        # runs in the current shell
# =============================================================================

_rt_die() {
    echo "Error: $*" >&2
    return 1 2>/dev/null || exit 1
}

THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
[ -n "$THIS_DIR" ] || { _rt_die "could not resolve script directory"; return 1 2>/dev/null || exit 1; }

BATCH="$THIS_DIR/run_spx_batch_cw305.sh"
[ -f "$BATCH" ] || { _rt_die "missing $BATCH (run_spx_batch_cw305.sh)"; return 1 2>/dev/null || exit 1; }

mapfile -t SCRIPTS < <(find "$THIS_DIR" -mindepth 2 -maxdepth 6 -name 'run.sh' \
                            -printf '%h/run.sh\n' 2>/dev/null | sort)

if (( ${#SCRIPTS[@]} == 0 )); then
    _rt_die "no per-test run.sh scripts found under $THIS_DIR/.../run.sh"
    return 1 2>/dev/null || exit 1
fi

echo
echo "╔════════════════════════════════════════════════════════╗"
echo "║  HASH Coprocessor Tests Selector  [CW305 build flags]  ║"
echo "╚════════════════════════════════════════════════════════╝"
echo
echo "Available tests:"

LABELS=()
for i in "${!SCRIPTS[@]}"; do
    dir=$(dirname "${SCRIPTS[$i]}")
    rel="${dir#$THIS_DIR/}"
    name=$(basename "$dir")
    if [[ "$rel" == pqc/baseline/DS/SLH-DSA/* ]]; then
        tag="[CW305 ✓ baseline]"
    elif [[ "$rel" == pqc/optimized/DS/SLH-DSA/* ]]; then
        tag="[CW305 ✓ optimized]"
    else
        tag="[default flags — CW305 N/A]"
    fi
    LABELS+=("$tag")
    printf "  [%2d] %-55s %s\n" "$i" "$rel" "$tag"
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

SCRIPT="${SCRIPTS[$IDX]}"
NAME=$(basename "$(dirname "$SCRIPT")")
SELDIR=$(dirname "$SCRIPT")
SELREL="${SELDIR#$THIS_DIR/}"

# --- SPHINCS+ path: route through CW305 batch driver -----------------------

if [[ "$SELREL" == pqc/baseline/DS/SLH-DSA/* || "$SELREL" == pqc/optimized/DS/SLH-DSA/* ]]; then
    if [[ "$SELREL" == pqc/baseline/* ]]; then mode="baseline"; else mode="optimized"; fi
    variant="$NAME"

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
    echo "Running (CW305 build): $mode / $variant / ${phases[*]}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo
    bash "$BATCH" --mode "$mode" --variants "$variant" "${phases[@]}"
    RT_RC=$?
else
    echo
    echo "⚠ '$NAME' is not a SPHINCS+ variant — CW305 build flags do not apply."
    echo "  Falling back to the test's default run.sh."
    echo
    bash "$SCRIPT"
    RT_RC=$?
fi

if (( RT_RC != 0 )); then
    echo "Error: '$NAME' exited with status $RT_RC" >&2
    return $RT_RC 2>/dev/null || exit $RT_RC
fi

return 0 2>/dev/null || exit 0
