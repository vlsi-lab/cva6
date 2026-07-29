#!/bin/bash

# Source environment setup
source ./verif/sim/setup-env.sh

# Simulation options
export DV_OPTS="$DV_OPTS --issrun_opts=+time_out=100000000000"
DV_TARGET=cv64a6_imac_crypto
export DV_SIMULATORS=veri-testharness
unset TRACE_FAST

#make clean
#make -C verif/sim clean_all

cd ./verif/sim/

ASM_FILE=""

src_main=../../tests/ml-kem-512-ascon/main.c
src_incs=(
	../../tests/ml-kem-512-ascon/ascon.c
	../../tests/ml-kem-512-ascon/cbd.c
	../../tests/ml-kem-512-ascon/indcpa.c
	../../tests/ml-kem-512-ascon/kem.c
	../../tests/ml-kem-512-ascon/ntt.c
	../../tests/ml-kem-512-ascon/poly.c
	../../tests/ml-kem-512-ascon/polyvec.c
	../../tests/ml-kem-512-ascon/randombytes.c
	../../tests/ml-kem-512-ascon/reduce.c
	../../tests/ml-kem-512-ascon/symmetric-ascon.c
	../../tests/ml-kem-512-ascon/verify.c
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
	-I../../tests/ml-kem-512-ascon/inc
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
