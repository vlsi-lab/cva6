#!/bin/bash

# Source environment setup
source ./verif/sim/setup-env.sh

# Simulation options
export DV_OPTS="$DV_OPTS --issrun_opts=+time_out=100000000000"
DV_TARGET=cv64a6_imac_crypto_vec
export DV_SIMULATORS=veri-testharness

#unset TRACE_FAST
export TRACE_FAST=1 

# Root optimized_vec directory
BASE_DIR="./tests/optimized_vec"

# List immediate subfolders (one level)
mapfile -t TEST_FOLDERS < <(find "$BASE_DIR" -mindepth 1 -maxdepth 1 -type d | sort)

if (( ${#TEST_FOLDERS[@]} == 0 )); then
    echo "No subfolders found in $BASE_DIR"
    return 1 2>/dev/null || exit 1
fi

echo ""
echo "Available optimized_vec folders:"
for i in "${!TEST_FOLDERS[@]}"; do
    echo "[$i] ${TEST_FOLDERS[$i]}"
done

echo ""
read -p "Select a folder (number): " FIDX

SELECTED_DIR="${TEST_FOLDERS[$FIDX]}"
echo ""
echo "Selected folder: $SELECTED_DIR"
echo ""

# Collect .c tests from the selected folder (one level)
mapfile -t CFILES < <(find "$SELECTED_DIR" -maxdepth 1 -name "*.c" | sort)

if (( ${#CFILES[@]} == 0 )); then
    echo "No .c files found in $SELECTED_DIR"
    return 1 2>/dev/null || exit 1
fi

echo "Available tests in $(basename "$SELECTED_DIR"):"
for i in "${!CFILES[@]}"; do
    echo "[$i] ${CFILES[$i]}"
done

echo ""
read -p "Select a test (number): " INDEX

SELECTED_TEST="${CFILES[$INDEX]}"
echo "Running $SELECTED_TEST"
echo ""

# Optional assembly (same rule as before)
ASM_FILE=""
if [[ "$SELECTED_TEST" == *"asm"* ]]; then
    # Try to find keccak_permute.s in the selected folder first, then fall back to old path
    if [[ -f "$SELECTED_DIR/keccak_permute.s" ]]; then
        ASM_FILE="../../${SELECTED_DIR#./}/keccak_permute.s"
    elif [[ -f "./tests/keccak64/keccak_permute.s" ]]; then
        ASM_FILE="../../tests/keccak64/keccak_permute.s"
    else
        echo "Warning: 'asm' test selected, but keccak_permute.s was not found."
    fi

    if [[ -n "$ASM_FILE" ]]; then
        echo "Including assembly file: $(basename "$ASM_FILE")"
    fi
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

# Include directory: prefer selected_folder/include, otherwise optimized_vec/include, otherwise nothing
EXTRA_INCLUDE=""
if [[ -d "../../${SELECTED_DIR#./}/include" ]]; then
    EXTRA_INCLUDE="-I../../${SELECTED_DIR#./}/include"
elif [[ -d "../../tests/optimized_vec/include" ]]; then
    EXTRA_INCLUDE="-I../../tests/optimized_vec/include"
fi

cflags=(
    "${cflags_opt[@]}"
    -I../tests/custom/env
    -I../tests/custom/common
    $EXTRA_INCLUDE
)

python3 cva6.py \
    --target=$DV_TARGET \
    --iss="$DV_SIMULATORS" \
    --iss_yaml=cva6.yaml \
    --c_tests "$src_main" \
    --sv_seed 1 \
    --gcc_opts "${src_incs[*]} ${src_common[*]} ${cflags[*]}" \
    --iss_timeout 1000000 \
    --linker=../tests/custom/common/test.ld \
    $DV_OPTS

cd ../..
