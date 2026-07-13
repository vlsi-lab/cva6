#!/bin/bash

# Source environment setup
source ./verif/sim/setup-env.sh

# Simulation options
export DV_OPTS="$DV_OPTS --issrun_opts=+time_out=100000000000"
DV_TARGET=cv64a6_imafdc_sv39
export DV_SIMULATORS=veri-testharness
unset TRACE_FAST

#make clean
#make -C verif/sim clean_all

cd ./verif/sim/

ASM_FILE=""
USE_COPRO=""
if [[ $1 == "copro" ]]; then
    USE_COPRO="-DUSE_COPROCESSOR_AXI"
    echo "Using AXI coprocessor for Ascon P12"
fi

src_main=../../tests/PQC-ascon/ML-DSA-5/main.c
src_incs=(
	../../tests/PQC-ascon/ML-DSA-5/ascon.c
	../../tests/PQC-ascon/ML-DSA-5/ntt.c
	../../tests/PQC-ascon/ML-DSA-5/packing.c
	../../tests/PQC-ascon/ML-DSA-5/poly.c
	../../tests/PQC-ascon/ML-DSA-5/polyvec.c
	../../tests/PQC-ascon/ML-DSA-5/reduce.c
	../../tests/PQC-ascon/ML-DSA-5/rounding.c
	../../tests/PQC-ascon/ML-DSA-5/sign.c
	../../tests/PQC-ascon/ML-DSA-5/symmetric-ascon.c
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
	$USE_COPRO
)

cflags=(
    "${cflags_opt[@]}"
    -DDILITHIUM_MODE=5
    -I../tests/custom/env
    -I../tests/custom/common
	-I../../tests/PQC-ascon/ML-DSA-5
    -I../../ascon/sw
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
