#!/bin/bash
# =============================================================================
# Per-test runner for "keccak-abs".
#
# Mirrors the structure of cva6/tests/ml-kem-512/run.sh / hello-world/run.sh
# (the known-good reference) so the cycle-counter / CSR access path runs
# reliably.
#
# Run from the cva6 repo root:
#     bash tests/keccak-abs/run.sh
# or via the picker:
#     bash tests/run_tests.sh
# =============================================================================
: "${LD_LIBRARY_PATH:=}"; export LD_LIBRARY_PATH

THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_NAME="keccak-abs"
TESTS_ROOT="$(cd "$THIS_DIR/.." && pwd)"
REPO_ROOT="$(cd "$TESTS_ROOT/.." && pwd)"

cd "$REPO_ROOT"

# Source environment setup
source ./verif/sim/setup-env.sh

# RTL watchdog & cva6.py wall-clock timeout (matches ml-kem-512).
TEST_TIMEOUT="${HASH_TEST_TIMEOUT:-100000000000}"
ISS_TIMEOUT="${HASH_ISS_TIMEOUT:-1000000}"

# Simulation options.
export DV_OPTS="${DV_OPTS:-} --issrun_opts=+time_out=${TEST_TIMEOUT}"
DV_TARGET=cv64a6_imafdc_sv39
export DV_SIMULATORS="${DV_SIMULATORS:-veri-testharness}"
unset TRACE_FAST

PYTHON=python3
command -v python3.9 >/dev/null 2>&1 && PYTHON=python3.9

cd ./verif/sim/

src_main=../../tests/keccak-abs/main.c

# Companion sources (every .c except main.c, plus every .S in the test dir).
src_incs=(
    ../../tests/keccak-abs/fips202.c
    ../../tests/keccak-abs/hash_coproc.S
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
    -I../../tests/keccak-abs
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
exit $RC
