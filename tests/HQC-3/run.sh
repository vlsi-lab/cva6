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
    --c_tests ../../tests/HQC-3/main.c \
    --iss_timeout 1000000 --issrun_opts="+time_out=100000000000" \
    --linker=../tests/custom/common/test.ld \
    --gcc_opts="-static -mcmodel=medany -fvisibility=hidden -02 \
    -funroll-loops -finline-functions \
    -nostartfiles -g ../tests/custom/common/syscalls.c \
    ../tests/custom/common/crt.S \
    ../../tests/HQC-3/code.c \
    ../../tests/HQC-3/crypto_memset.c \
    ../../tests/HQC-3/fft.c \
    ../../tests/HQC-3/fips202.c \
    ../../tests/HQC-3/gf.c \
    ../../tests/HQC-3/gf2x.c \
    ../../tests/HQC-3/hqc.c \
    ../../tests/HQC-3/kem.c \
    ../../tests/HQC-3/parsing.c \
    ../../tests/HQC-3/reed_muller.c \
    ../../tests/HQC-3/reed_solomon.c \
    ../../tests/HQC-3/symmetric.c \
    ../../tests/HQC-3/vector.c \
    -lgcc -fstack-usage\
    -I../tests/custom/env -I../tests/custom/common -I../../tests/HQC-3"

cd ..
cd ..



