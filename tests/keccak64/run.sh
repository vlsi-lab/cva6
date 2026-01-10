#!/bin/bash

# Source environment setup
source ./verif/sim/setup-env.sh

# Simulation options
export DV_OPTS="$DV_OPTS"
DV_TARGET=cv64a6_imac_crypto
export DV_SIMULATORS=veri-testharness
unset TRACE_FAST
#export TRACE_FAST=1

#make clean
#make -C verif/sim clean_all

TEST_DIR="./tests/keccak64"
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

# Check if filename contains "asm" to include assembly file
ASM_FILE=""
if [[ "$SELECTED_TEST" == *"asm"* ]]; then
    ASM_FILE="../../tests/keccak64/keccak_permute.s"
    echo "Including assembly file: keccak_permute.s"
fi

cd ./verif/sim/

src_main=../../$SELECTED_TEST

src_incs=(
	$ASM_FILE
)
src_common=(
    ../tests/custom/common/syscalls.c
    ../tests/custom/common/crt.S
)

cflags_opt=(
    -O2 -g
    -fno-tree-loop-distribute-patterns
    -static
    -mcmodel=medany
    -fvisibility=hidden
    -nostartfiles
    -lgcc
    -funroll-all-loops
	-finline-functions
    -Wl,-gc-sections
)

cflags=(
    "${cflags_opt[@]}"
    -I../tests/custom/env
    -I../tests/custom/common
	-I../../tests/keccak64/include
	-I../../keccak_ip/sw
)

python3 cva6.py \
    --target=$DV_TARGET \
    --iss="$DV_SIMULATORS" \
    --iss_yaml=cva6.yaml \
    --c_tests "$src_main" \
    --sv_seed 1 \
    --gcc_opts "${src_incs[*]} ${src_common[*]} ${cflags[*]}" \
	--linker=../tests/custom/common/test.ld \
    $DV_OPTS

cd ../..