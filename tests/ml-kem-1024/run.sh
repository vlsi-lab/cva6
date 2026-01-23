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
    --c_tests ../../tests/ml-kem-1024/main.c \
    --iss_timeout 1000000 --issrun_opts="+time_out=100000000000" \
    --linker=../tests/custom/common/test.ld \
    --gcc_opts="-static -mcmodel=medany -fvisibility=hidden -02 \
    -funroll-loops -finline-functions \
    -nostartfiles -g ../tests/custom/common/syscalls.c \
    ../tests/custom/common/crt.S \
    ../../tests/ml-kem-1024/cbd.c \
    ../../tests/ml-kem-1024/fips202.c \
    ../../tests/ml-kem-1024/indcpa.c \
    ../../tests/ml-kem-1024/kem.c \
    ../../tests/ml-kem-1024/ntt.c \
    ../../tests/ml-kem-1024/poly.c \
    ../../tests/ml-kem-1024/polyvec.c \
    ../../tests/ml-kem-1024/randombytes.c \
    ../../tests/ml-kem-1024/reduce.c \
    ../../tests/ml-kem-1024/symmetric-shake.c \
    ../../tests/ml-kem-1024/verify.c \
    -lgcc -fstack-usage\
    -I../tests/custom/env -I../tests/custom/common -I../../tests/ml-kem-1024/inc"

cd ..
cd ..



