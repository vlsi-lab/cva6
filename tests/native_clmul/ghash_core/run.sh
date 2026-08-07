#!/bin/bash

# Source environment setup
source ./verif/sim/setup-env.sh

DV_TARGET=cv64a6_imac_crypto
export DV_SIMULATORS=veri-testharness
export TRACE_FAST=1

cd ./verif/sim

src_main=../../tests/native_clmul/ghash_core/ghash_core.c

src_common=(
    ../tests/custom/common/syscalls.c
    ../tests/custom/common/crt.S
    ../../tests/native_clmul/common/ghash.c
)

cflags=(
    -O2 -g
    -fno-tree-loop-distribute-patterns
    -static
    -mcmodel=medany
    -fvisibility=hidden
    -nostartfiles
    -lgcc

    -I../tests/custom/env
    -I../tests/custom/common
    -I../../tests/native_clmul/common
    -I../../tests/software/common
)

python3 cva6.py \
    --target=$DV_TARGET \
    --iss="$DV_SIMULATORS" \
    --iss_yaml=cva6.yaml \
    --c_tests "$src_main" \
    --gcc_opts "${src_common[*]} ${cflags[*]}" \
    --linker=../tests/custom/common/test.ld
RESULT=$?

cd ../..
exit $RESULT
