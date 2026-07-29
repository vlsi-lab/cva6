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

src_main=../../tests/FAEST_EM_128S/main.c
src_incs=(
	../../tests/FAEST_EM_128S/KeccakHash.c
	../../tests/FAEST_EM_128S/KeccakP-1600-opt64.c
	../../tests/FAEST_EM_128S/KeccakSponge.c
	../../tests/FAEST_EM_128S/aes.c
	../../tests/FAEST_EM_128S/bavc.c
	../../tests/FAEST_EM_128S/compat.c
	../../tests/FAEST_EM_128S/cpu.c
	../../tests/FAEST_EM_128S/crypto_sign.c
	../../tests/FAEST_EM_128S/faest_em_128s.c
	../../tests/FAEST_EM_128S/faest_aes_128.c
	../../tests/FAEST_EM_128S/faest_aes_192.c
	../../tests/FAEST_EM_128S/faest_aes_256.c
	../../tests/FAEST_EM_128S/faest_impl.c
	../../tests/FAEST_EM_128S/fields.c
	../../tests/FAEST_EM_128S/instances.c
	../../tests/FAEST_EM_128S/owf.c
	../../tests/FAEST_EM_128S/random_oracle.c
	../../tests/FAEST_EM_128S/randomness.c
	../../tests/FAEST_EM_128S/rng.c
	../../tests/FAEST_EM_128S/universal_hashing.c
	../../tests/FAEST_EM_128S/utils.c
	../../tests/FAEST_EM_128S/vole.c
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
	-I../../tests/FAEST_EM_128S
	-I../../tests/FAEST_EM_128S/inc
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
