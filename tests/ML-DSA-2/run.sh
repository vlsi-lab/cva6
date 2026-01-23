#!/bin/bash

# Source environment setup
source ./verif/sim/setup-env.sh

#DV_TARGET=cv64a6_imafdc_sv39
DV_TARGET=cv64a6_imac_crypto

# Set the NUM_JOBS variable to increase the number of parallel make jobs
# export NUM_JOBS=

export DV_SIMULATORS=veri-testharness
# export DV_SIMULATORS=spike
#export TRACE_FAST=1

cd ./verif/sim



python3 cva6.py --target=$DV_TARGET --iss=$DV_SIMULATORS --iss_yaml=cva6.yaml \
    --c_tests ../../tests/ML-DSA-2/main.c \
    --iss_timeout 1000000 --issrun_opts="+time_out=100000000000" \
    --linker=../tests/custom/common/test.ld \
    --gcc_opts="-static -mcmodel=medany -fvisibility=hidden -02 \
    -funroll-loops -finline-functions \
    -nostartfiles -g ../tests/custom/common/syscalls.c \
    ../tests/custom/common/crt.S \
    ../../tests/ML-DSA-2/fips202.c \
    ../../tests/ML-DSA-2/ntt.c \
    ../../tests/ML-DSA-2/packing.c \
    ../../tests/ML-DSA-2/poly.c \
    ../../tests/ML-DSA-2/polyvec.c \
    ../../tests/ML-DSA-2/randombytes.c \
    ../../tests/ML-DSA-2/reduce.c \
    ../../tests/ML-DSA-2/rounding.c \
    ../../tests/ML-DSA-2/sign.c \
    ../../tests/ML-DSA-2/symmetric-shake.c \
    -lgcc -fstack-usage\
    -I../tests/custom/env -I../tests/custom/common -I../../tests/ML-DSA-2/inc"

cd ..
cd ..



