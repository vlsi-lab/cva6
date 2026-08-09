#!/bin/bash
# =============================================================================
# Per-test runner for ML-DSA-65 (Dilithium2) baseline test.
# =============================================================================
: "${LD_LIBRARY_PATH:=}"; export LD_LIBRARY_PATH

THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_NAME="ML-DSA-baseline-ML-DSA-65"
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

TEST_DIR=../../tests/vrf/optimized/ML-DSA-65

src_main="$TEST_DIR/ML-DSA-65_optimized.c"

src_incs=(
    "$TEST_DIR/fips202.c"
    "$TEST_DIR/ntt.c"
    "$TEST_DIR/packing.c"
    "$TEST_DIR/poly.c"
    "$TEST_DIR/polyvec.c"
    "$TEST_DIR/reduce.c"
    "$TEST_DIR/rounding.c"
    "$TEST_DIR/sign.c"
    "$TEST_DIR/symmetric-shake.c"
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
    -Wl,-gc-sections
)

cflags=(
    "${cflags_opt[@]}"
    -I../tests/custom/env
    -I../tests/custom/common
    -I"$TEST_DIR"
    -I../../vrf_ip/sw
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
