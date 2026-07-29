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

src_main=../../tests/FAEST_192S/main.c
src_incs=(
	../../tests/FAEST_192S/KeccakHash.c
	../../tests/FAEST_192S/KeccakP-1600-opt64.c
	../../tests/FAEST_192S/KeccakSponge.c
	../../tests/FAEST_192S/aes.c
	../../tests/FAEST_192S/bavc.c
	../../tests/FAEST_192S/compat.c
	../../tests/FAEST_192S/cpu.c
	../../tests/FAEST_192S/crypto_sign.c
	../../tests/FAEST_192S/faest_192s.c
	../../tests/FAEST_192S/faest_aes_128.c
	../../tests/FAEST_192S/faest_aes_192.c
	../../tests/FAEST_192S/faest_aes_256.c
	../../tests/FAEST_192S/faest_impl.c
	../../tests/FAEST_192S/fields.c
	../../tests/FAEST_192S/instances.c
	../../tests/FAEST_192S/owf.c
	../../tests/FAEST_192S/random_oracle.c
	../../tests/FAEST_192S/randomness.c
	../../tests/FAEST_192S/rng.c
	../../tests/FAEST_192S/universal_hashing.c
	../../tests/FAEST_192S/utils.c
	../../tests/FAEST_192S/vole.c
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
	-I../../tests/FAEST_192S
	-I../../tests/FAEST_192S/inc
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
