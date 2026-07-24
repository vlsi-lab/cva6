#!/bin/bash

# Standalone hardware-vs-software test/benchmark suite for ntt_engine.sv
# (mp_NTT/mp_iNTT/mp_NTT_autoadj and vect_FFT/vect_iFFT -- see
# NTT_ACCEL_DESIGN.md). Mirrors tests/keccak64/run.sh's interactive
# pick-a-test pattern.
#
# Each test links only its own .c file plus whichever of ng_mp31.c
# (mp_NTT/mp_iNTT tests) or ng_fxp.c (vect_FFT/vect_iFFT tests) it needs --
# both link cleanly on their own (no other ntrugen sources required, since
# neither calls into SHA3/zint/poly code -- only ng_inner.h's declarations,
# satisfied by the headers in this directory).

# Source environment setup
source ./verif/sim/setup-env.sh

# Simulation options
export DV_OPTS="$DV_OPTS --issrun_opts=+time_out=100000000000"
DV_TARGET=cv64a6_imac_crypto
export DV_SIMULATORS=veri-testharness
unset TRACE_FAST
#export TRACE_FAST=1

TEST_DIR="./tests/ntt_fft"
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

# Link ng_mp31.c for the mp_NTT/mp_iNTT tests, ng_fxp.c for the
# vect_FFT/vect_iFFT test -- selected by filename, same convention as
# run_*.sh in tests/hawk-256-keccak this suite was split out of. Both live
# in inc/ (not this directory) so they don't show up as selectable "tests"
# themselves -- neither has a main().
NTRUGEN_SRC="../../tests/ntt_fft/inc/ng_mp31.c"
if [[ "$SELECTED_TEST" == *"fft_engine_test.c"* ]]; then
    NTRUGEN_SRC="../../tests/ntt_fft/inc/ng_fxp.c"
fi

cd ./verif/sim/

src_main=../../$SELECTED_TEST

src_common=(
    "$NTRUGEN_SRC"
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
    -I../../tests/ntt_fft
    -I../../keccak_ip/sw
)

python3 cva6.py \
    --target=$DV_TARGET \
    --iss="$DV_SIMULATORS" \
    --iss_yaml=cva6.yaml \
    --c_tests "$src_main" \
    --sv_seed 1 \
    --gcc_opts "${src_common[*]} ${cflags[*]}" \
    --linker=../tests/custom/common/test.ld \
    $DV_OPTS

cd ../..
