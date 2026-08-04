#!/bin/bash

# Source environment setup
source ./verif/sim/setup-env.sh

DV_TARGET=cv64a6_imafdc_sv39
export DV_SIMULATORS=veri-testharness
export TRACE_FAST=1

cd ./verif/sim

src_main=../../tests/aes64_xif_tests/aes128_full.c
src_common=(
    ../tests/custom/common/syscalls.c
    ../tests/custom/common/crt.S
)

cflags=(
    -O0 -g
    -static
    -mcmodel=medany
    -fvisibility=hidden
    -nostartfiles
    -lgcc
    -I../tests/custom/env
    -I../tests/custom/common
)

python3 cva6.py \
    --target=$DV_TARGET \
    --iss="$DV_SIMULATORS" \
    --iss_yaml=cva6.yaml \
    --c_tests "$src_main" \
    --gcc_opts "${src_common[*]} ${cflags[*]}" \
    --linker=../tests/custom/common/test.ld

cd ../..
