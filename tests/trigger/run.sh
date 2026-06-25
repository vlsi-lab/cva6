#!/bin/bash
# =============================================================================
# Per-test runner for "trigger".
#
# Mirrors the structure of tests/hello-world/run.sh.
#
# Run from the cva6 repo root:
#     bash tests/trigger/run.sh
# =============================================================================
: "${LD_LIBRARY_PATH:=}"; export LD_LIBRARY_PATH

THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_NAME="trigger"
TESTS_ROOT="$(cd "$THIS_DIR/.." && pwd)"
REPO_ROOT="$(cd "$TESTS_ROOT/.." && pwd)"

cd "$REPO_ROOT"

# Source environment setup
source ./verif/sim/setup-env.sh

TEST_TIMEOUT="${HASH_TEST_TIMEOUT:-100000000000}"
ISS_TIMEOUT="${HASH_ISS_TIMEOUT:-1000000}"

export DV_OPTS="${DV_OPTS:-} --issrun_opts=+time_out=${TEST_TIMEOUT}"
DV_TARGET=cv64a6_imafdc_sv39
export DV_SIMULATORS="${DV_SIMULATORS:-veri-testharness}"

# ---------------------------------------------------------------------------
# Waveform dump (VCD) — enable so the trigger pulse can be inspected in GTKWave.
# TRACE_FAST=1 in the cva6 build => Verilator is rebuilt with --trace and the
# Variane_testharness binary is invoked with `-v verilator.vcd`. The driver
# Makefile renames it to <log>.vcd next to the run log.
# Set HASH_NO_VCD=1 to disable.
# ---------------------------------------------------------------------------
if [[ -z "${HASH_NO_VCD:-}" ]]; then
    export TRACE_FAST=1
    unset TRACE_COMPACT VERDI
    # The cached Verilator model was likely built without VM_TRACE; force a
    # rebuild so tracing hooks are present in the generated C++.
    if [[ -d "$REPO_ROOT/work-ver" ]] && \
       ! grep -q "VM_TRACE 1" "$REPO_ROOT/work-ver/Variane_testharness.h" 2>/dev/null; then
        echo "[trigger] Rebuilding Verilator model with VCD tracing enabled..."
        rm -rf "$REPO_ROOT/work-ver"
    fi
else
    unset TRACE_FAST
fi

PYTHON=python3
command -v python3.9 >/dev/null 2>&1 && PYTHON=python3.9

cd ./verif/sim/

src_main=../../tests/trigger/trigger.c
src_incs=(
)
src_common=(
    ../tests/custom/common/syscalls.c
    ../tests/custom/common/crt.S
)

cflags_opt=(
    -O2 -g
    -fno-tree-loop-distribute-patterns
    -static
    -mcmodel=medany
    -fvisibility=hidden
    -nostartfiles
    -lgcc
    -funroll-all-loops
    -finline-functions
    -Wl,-gc-sections
)

cflags=(
    "${cflags_opt[@]}"
    -I../tests/custom/env
    -I../tests/custom/common
    -I../../tests/trigger
    -I../../tests/inc
    -I../../tests
)

"$PYTHON" cva6.py \
    --target=$DV_TARGET \
    --iss="$DV_SIMULATORS" \
    --iss_yaml=cva6.yaml \
    --c_tests "$src_main" \
    --sv_seed 1 \
    --gcc_opts "${src_incs[*]} ${src_common[*]} ${cflags[*]}" \
    --iss_timeout "$ISS_TIMEOUT" \
    --linker=../tests/custom/common/test.ld \
    $DV_OPTS
RC=$?

cd "$REPO_ROOT"

if [[ $RC -ne 0 ]]; then
    echo ""
    echo "============================================================"
    echo "[trigger] FAILED with exit code $RC"
    echo "Shell kept open so you can inspect logs / re-run."
    echo "============================================================"
else
    echo "[trigger] PASSED"
fi

# Locate and report the freshest VCD so the user can open it in GTKWave.
if [[ -n "${TRACE_FAST:-}" ]]; then
    VCD_FILE="$(ls -t "$REPO_ROOT"/verif/sim/out_*/veri-testharness_sim/trigger.${DV_TARGET}.vcd 2>/dev/null | head -1)"
    if [[ -n "$VCD_FILE" ]]; then
        echo "[trigger] VCD: $VCD_FILE"
        echo "[trigger]   gtkwave \"$VCD_FILE\" &"
    else
        echo "[trigger] (no VCD produced — check log above)"
    fi
fi

# Do not exit the calling shell on failure: return RC if sourced,
# otherwise just leave RC in $? without slamming the terminal closed.
return $RC 2>/dev/null || true
