#!/bin/bash
# =============================================================================
# Per-test runner for "prf-addr" (PRF_ADDR SW-vs-HW via chain_job_ctrl).
#
# Same cva6.py / veri-testharness invocation pattern used by every other
# tests/app-tests/*/run.sh.
#
# Run from the cva6 repo root:
#     bash tests/app-tests/prf-addr/run.sh
# =============================================================================
: "${LD_LIBRARY_PATH:=}"; export LD_LIBRARY_PATH

THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TESTS_ROOT="$(cd "$THIS_DIR/.." && pwd)"
REPO_ROOT="$(cd "$TESTS_ROOT/../.." && pwd)"

cd "$REPO_ROOT"

# Source environment setup
source ./verif/sim/setup-env.sh

DV_TARGET=cv64a6_imac_crypto
export DV_SIMULATORS="${DV_SIMULATORS:-veri-testharness}"
unset TRACE_FAST

PYTHON=python3
command -v python3.9 >/dev/null 2>&1 && PYTHON=python3.9

cd ./verif/sim/

python3 cva6.py \
    --target=$DV_TARGET \
    --iss="$DV_SIMULATORS" \
    --iss_yaml=cva6.yaml \
    --c_tests ../../tests/app-tests/prf-addr/main.c \
    --linker=../tests/custom/common/test.ld \
    --gcc_opts="-static -mcmodel=medany -fvisibility=hidden -O2 -g \
        -fno-tree-loop-distribute-patterns \
        -nostartfiles \
        ../tests/custom/common/syscalls.c \
        ../tests/custom/common/crt.S \
        -lgcc \
        -I../tests/custom/env \
        -I../tests/custom/common \
        -I../../tests/app-tests/prf-addr \
        -I../../vrf_ip/sw"
RC=$?

cd "$REPO_ROOT"
exit $RC
