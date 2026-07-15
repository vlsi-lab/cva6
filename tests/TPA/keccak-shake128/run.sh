#!/bin/bash
#
# Builds and runs the Keccak-f[1600] TPA benchmark for SHAKE128 (r=1344 bits)
# on the cva6 RTL simulator. Prints the permutation cycle count (C_perm)
# needed for TPA = r * f_clk / (C_perm * A).
#
# Usage:
#   tests/TPA/keccak-shake128/run.sh          # original: pure-software permutation
#   tests/TPA/keccak-shake128/run.sh copro    # optimized: Keccak AXI accelerator IP

source ./verif/sim/setup-env.sh

export DV_OPTS="$DV_OPTS"
DV_TARGET=cv64a6_imac_crypto
export DV_SIMULATORS=veri-testharness
unset TRACE_FAST

cd ./verif/sim/

USE_COPRO=""
if [[ "$1" == "copro" ]]; then
    USE_COPRO="-DUSE_COPROCESSOR_AXI"
    echo "Using Keccak AXI accelerator (optimized)"
else
    echo "Using pure-software permutation (original)"
fi

src_main=../../tests/TPA/keccak-shake128/main.c

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
    -I../tests/custom/env
    -I../tests/custom/common
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
