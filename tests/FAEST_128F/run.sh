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

src_main=../../tests/FAEST_128F/main.c
src_incs=(
	../../tests/FAEST_128F/KeccakHash.c
	../../tests/FAEST_128F/KeccakP-1600-opt64.c
	../../tests/FAEST_128F/KeccakSponge.c
	../../tests/FAEST_128F/aes.c
	../../tests/FAEST_128F/bavc.c
	../../tests/FAEST_128F/compat.c
	../../tests/FAEST_128F/cpu.c
	../../tests/FAEST_128F/crypto_sign.c
	../../tests/FAEST_128F/faest_128f.c
	../../tests/FAEST_128F/faest_aes_128.c
	../../tests/FAEST_128F/faest_aes_192.c
	../../tests/FAEST_128F/faest_aes_256.c
	../../tests/FAEST_128F/faest_impl.c
	../../tests/FAEST_128F/fields.c
	../../tests/FAEST_128F/instances.c
	../../tests/FAEST_128F/owf.c
	../../tests/FAEST_128F/random_oracle.c
	../../tests/FAEST_128F/randomness.c
	../../tests/FAEST_128F/rng.c
	../../tests/FAEST_128F/universal_hashing.c
	../../tests/FAEST_128F/utils.c
	../../tests/FAEST_128F/vole.c
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
	-I../../tests/FAEST_128F
	-I../../tests/FAEST_128F/inc
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
