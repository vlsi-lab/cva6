#!/bin/bash

# Source environment setup
source ./verif/sim/setup-env.sh

export AES_VARIANT=${AES_VARIANT:-loose_v2}
source ./scripts/select_aes_variant.sh || exit 1

export DV_SIMULATORS=veri-testharness
export TRACE_FAST=1

cd ./verif/sim

src_main=../../tests/loosely/kmac256/kmac256.c

src_common=(
    ../tests/custom/common/syscalls.c
    ../tests/custom/common/crt.S
    ../../tests/loosely/common/fips202.c
    ../../tests/loosely/common/keccak_permute_loosely.c
    ../../tests/loosely/common/kmac.c
    ../../kecc_aes_k_axi/sw/${AES_DRIVER_C:-kecc_aes_k_axi.c}
)

cflags=(
    -O2 -g
    -fno-tree-loop-distribute-patterns
    -static
    -mcmodel=medany
    -fvisibility=hidden
    -nostartfiles
    -lgcc

    -DUSE_COPROCESSOR_ASM
    -I../tests/custom/env
    -I../tests/custom/common
    -I../../tests/loosely/common
    -I../../kecc_aes_k_axi/sw
)

python3 cva6.py \
    --target=$DV_TARGET \
    --iss="$DV_SIMULATORS" \
    --iss_yaml=cva6.yaml \
    --c_tests "$src_main" \
    --gcc_opts "${src_common[*]} ${cflags[*]}" \
    --linker=../tests/custom/common/test.ld
RESULT=$?

cd ../..
exit $RESULT
