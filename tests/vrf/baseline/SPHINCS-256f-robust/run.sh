#!/bin/bash
# =============================================================================
# Per-test runner for SLH-DSA baseline tests.
# =============================================================================
: "${LD_LIBRARY_PATH:=}"; export LD_LIBRARY_PATH

THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_NAME="SLH-DSA-baseline-SPHINCS-256f-robust"
TESTS_ROOT="$(cd "$THIS_DIR/../../.." && pwd)"
REPO_ROOT="$(cd "$TESTS_ROOT/.." && pwd)"

cd "$REPO_ROOT" || { echo "Error: cannot cd to REPO_ROOT=$REPO_ROOT" >&2; return 1 2>/dev/null || exit 1; }

if [[ ! -f ./verif/sim/setup-env.sh ]]; then
    echo "Error: missing ./verif/sim/setup-env.sh from REPO_ROOT=$REPO_ROOT" >&2
    return 1 2>/dev/null || exit 1
fi
source ./verif/sim/setup-env.sh || { echo "Error: failed sourcing setup-env.sh" >&2; return 1 2>/dev/null || exit 1; }

TEST_TIMEOUT="${HASH_TEST_TIMEOUT:-100000000000}"
ISS_TIMEOUT="${HASH_ISS_TIMEOUT:-1000000}"

export DV_OPTS="${DV_OPTS:-} --issrun_opts=+time_out=${TEST_TIMEOUT}"
DV_TARGET=cv64a6_imafdc_sv39
export DV_SIMULATORS="${DV_SIMULATORS:-veri-testharness}"
unset TRACE_FAST

PYTHON=python3
command -v python3.9 >/dev/null 2>&1 && PYTHON=python3.9

cd ./verif/sim/ || { echo "Error: cannot cd ./verif/sim" >&2; return 1 2>/dev/null || exit 1; }

TEST_DIR=../../tests/vrf/baseline/SPHINCS-256f-robust
if [[ -f "$TEST_DIR/src/address.c" ]]; then
    SRC_BASE="$TEST_DIR/src"
else
    SRC_BASE="$TEST_DIR"
fi

src_main="$TEST_DIR/SPHINCS-256f-robust_baseline.c"

src_incs=(
    "$SRC_BASE/address.c"
    "$SRC_BASE/fips202.c"
    "$SRC_BASE/fors.c"
    "$SRC_BASE/hash_shake.c"
    "$SRC_BASE/merkle.c"
    "$SRC_BASE/randombytes.c"
    "$SRC_BASE/sign.c"
    "$SRC_BASE/thash_shake_robust.c"
    "$SRC_BASE/utils.c"
    "$SRC_BASE/utilsx1.c"
    "$SRC_BASE/wots.c"
    "$SRC_BASE/wotsx1.c"
)

if [[ "baseline" == "optimized" ]]; then
    src_incs+=("$SRC_BASE/keccak_coproc.S")
fi

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
    -Wl,-gc-sections
)

cflags=(
    "${cflags_opt[@]}"
    -I../tests/custom/env
    -I../tests/custom/common
    -I"$TEST_DIR"
    -I"$TEST_DIR/src"
    -I"$TEST_DIR/include"
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

cd "$REPO_ROOT" || true
return "$RC" 2>/dev/null || exit "$RC"
