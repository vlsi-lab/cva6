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
    --c_tests ../../tests/SPHINCS+-192f-simple/main.c \
    --iss_timeout 1000000 --issrun_opts="+time_out=100000000000" \
    --linker=../tests/custom/common/test.ld \
    --gcc_opts="-static -mcmodel=medany -fvisibility=hidden -02 \
    -funroll-loops -finline-functions \
    -nostartfiles -g ../tests/custom/common/syscalls.c \
    ../tests/custom/common/crt.S \
    ../../tests/SPHINCS+-192f-simple/address.c \
    ../../tests/SPHINCS+-192f-simple/fips202.c \
    ../../tests/SPHINCS+-192f-simple/fors.c \
    ../../tests/SPHINCS+-192f-simple/hash_shake.c \
    ../../tests/SPHINCS+-192f-simple/merkle.c \
    ../../tests/SPHINCS+-192f-simple/randombytes.c \
    ../../tests/SPHINCS+-192f-simple/sign.c \
    ../../tests/SPHINCS+-192f-simple/thash_shake_robust.c \
    ../../tests/SPHINCS+-192f-simple/utils.c \
    ../../tests/SPHINCS+-192f-simple/utilsx1.c \
    ../../tests/SPHINCS+-192f-simple/wots.c \
    ../../tests/SPHINCS+-192f-simple/wotsx1.c  \
    -lgcc -fstack-usage\
    -I../tests/custom/env -I../tests/custom/common -I../../tests/SPHINCS+-192f-simple" \

cd ..
cd ..



