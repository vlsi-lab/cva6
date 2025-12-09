#!/bin/bash

# Source environment setup
source ./verif/sim/setup-env.sh

DV_TARGET=cv64a6_imafdc_sv39

# Set the NUM_JOBS variable to increase the number of parallel make jobs
# export NUM_JOBS=

export DV_SIMULATORS=veri-testharness
# export DV_SIMULATORS=spike
#export TRACE_FAST=1

TEST_DIR="./tests/keccak"
mapfile -t CFILES < <(find "$TEST_DIR" -maxdepth 1 -name "*.c" | sort)

if (( ${#CFILES[@]} == 0 )); then
    echo "No .c files found in $TEST_DIR"
    exit 1
fi

echo ""
echo "Available tests:"
for i in "${!CFILES[@]}"; do
    echo "[$i] ${CFILES[$i]}"
done

echo ""
read -p "Select a test (number): " INDEX

SELECTED_TEST="${CFILES[$INDEX]}"
echo "Running $SELECTED_TEST"
echo ""

cd ./verif/sim

python3 cva6.py --target cv64a6_imafdc_sv39 --iss=$DV_SIMULATORS --iss_yaml=cva6.yaml \
--c_tests ../../$SELECTED_TEST \
--linker=../tests/custom/common/test.ld \
--gcc_opts="-static -mcmodel=medany -fvisibility=hidden -O0 \
-nostartfiles -g ../tests/custom/common/syscalls.c \
../tests/custom/common/crt.S -lgcc \
-I../tests/custom/env -I../tests/custom/common -I../../tests/keccak/include"

cd ..
cd ..


