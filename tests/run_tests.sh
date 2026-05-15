#!/bin/bash
# =============================================================================
# tests/run_tests.sh - Interactive picker that dispatches to a per-test
# `run.sh`.  Each tests/<test>/run.sh is self-contained and known to work.
#
# Usage (from the cva6 repo root, either way works):
#     bash   tests/run_tests.sh        # spawns a child shell
#     source tests/run_tests.sh        # runs in the current shell
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

mapfile -t SCRIPTS < <(find "$THIS_DIR" -mindepth 2 -maxdepth 2 -name 'run.sh' \
                            -printf '%h/run.sh\n' 2>/dev/null | sort)

if (( ${#SCRIPTS[@]} == 0 )); then
    _rt_die "no per-test run.sh scripts found under $THIS_DIR/<test>/run.sh"
    return 1 2>/dev/null || exit 1
fi

echo
echo "Available HASH coprocessor tests:"
for i in "${!SCRIPTS[@]}"; do
    name=$(basename "$(dirname "${SCRIPTS[$i]}")")
    printf "  [%2d] %s\n" "$i" "$name"
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
echo "Running test: $NAME -> $SCRIPT"
echo

# Always run the per-test script in its own subshell so its `set -u`,
# `cd`, env tweaks, traps, etc. cannot affect the calling shell.  Capture
# the exit status and report it without ever calling `exit` on a sourced
# parent shell.
bash "$SCRIPT"
RT_RC=$?

if (( RT_RC != 0 )); then
    echo "Error: '$NAME' exited with status $RT_RC" >&2
    return $RT_RC 2>/dev/null || exit $RT_RC
fi

return 0 2>/dev/null || exit 0
