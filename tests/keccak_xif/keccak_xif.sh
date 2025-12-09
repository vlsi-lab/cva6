#!/bin/bash

# Source environment setup
source ./verif/sim/setup-env.sh

DV_TARGET=cv64a6_imafdc_sv39

# Set the NUM_JOBS variable to increase the number of parallel make jobs
# export NUM_JOBS=

export DV_SIMULATORS=veri-testharness
# export DV_SIMULATORS=spike
export TRACE_FAST=1

cd ./verif/sim

python3 cva6.py --target cv64a6_imafdc_sv39 --iss=$DV_SIMULATORS --iss_yaml=cva6.yaml \
--asm_tests ../../tests/keccak_xif/keccak_xif.S \
--linker=../tests/custom/common/test.ld \
--gcc_opts="-static -mcmodel=medany -fvisibility=hidden -O0 \
-nostartfiles -g ../tests/custom/common/syscalls.c \
../tests/custom/common/crt.S -lgcc \
-I../tests/custom/env -I../tests/custom/common"

cd ..
cd ..

