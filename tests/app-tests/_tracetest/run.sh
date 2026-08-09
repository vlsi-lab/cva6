#!/bin/bash
: "${LD_LIBRARY_PATH:=}"; export LD_LIBRARY_PATH
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TESTS_ROOT="$(cd "$THIS_DIR/.." && pwd)"
REPO_ROOT="$(cd "$TESTS_ROOT/../.." && pwd)"
cd "$REPO_ROOT"
source ./verif/sim/setup-env.sh
DV_TARGET=cv64a6_imac_crypto
export DV_SIMULATORS="${DV_SIMULATORS:-veri-testharness}"
export TRACE_FAST="${TRACE_FAST:-}"
cd ./verif/sim/
python3 cva6.py \
    --target=$DV_TARGET \
    --iss="$DV_SIMULATORS" \
    --iss_yaml=cva6.yaml \
    --iss_timeout "${ISS_TIMEOUT:-120}" \
    --sv_seed "${SEED:-1}" \
    --c_tests ../../tests/app-tests/_tracetest/main.c \
    --linker=../tests/custom/common/test.ld \
    --gcc_opts="-static -mcmodel=medany -fvisibility=hidden -O0 -g \
        -nostartfiles \
        ../tests/custom/common/syscalls.c \
        ../tests/custom/common/crt.S \
        -lgcc \
        -I../tests/custom/env \
        -I../tests/custom/common \
        -I../../hashpq_ip/sw"
RC=$?
cd "$REPO_ROOT"
exit $RC
