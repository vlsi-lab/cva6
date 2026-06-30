#!/bin/bash
# ****************************************************************************
#
# Auth: Alessandra Dolmeta - Politecnico di Torino
# Date: June 2025
# Desc: Run HAWK-1024 KAT + cycle profiling on the CVA6 simulator.
#       Measures clock cycles for keygen, sign and verify using the
#       RISC-V mcycle CSR. Results are printed via the simulated UART.
#
# Usage:
#   ./run.sh          - reference software only
#   ./run.sh copro    - swap in the keccak64 coprocessor assembly for SHA-3
#
# ****************************************************************************

# Must be run from the CVA6 repository root
source ./verif/sim/setup-env.sh

# Simulation options
export DV_OPTS="$DV_OPTS --issrun_opts=+time_out=100000000000"
DV_TARGET=cv64a6_imac_crypto
export DV_SIMULATORS=veri-testharness
unset TRACE_FAST

# Optional: inject the keccak64 coprocessor assembly
ASM_FILE=""
USE_COPRO=""
if [[ $1 == "copro" ]]; then
    ASM_FILE="../../tests/keccak64/keccak_permute.s"
    USE_COPRO="-DUSE_COPROCESSOR_ASM"
    echo "Using coprocessor assembly implementation for KeccakF1600_StatePermute"
fi

# ---- Source files -------------------------------------------------------
src_main=../../tests/hawk-1024/main.c

src_incs=(
    # HAWK core implementation
    ../../tests/hawk-1024/hawk_kgen.c
    ../../tests/hawk-1024/hawk_sign.c
    ../../tests/hawk-1024/hawk_vrfy.c
    # NTT / polynomial helpers
    ../../tests/hawk-1024/ng_fxp.c
    ../../tests/hawk-1024/ng_hawk.c
    ../../tests/hawk-1024/ng_mp31.c
    ../../tests/hawk-1024/ng_ntru.c
    ../../tests/hawk-1024/ng_poly.c
    ../../tests/hawk-1024/ng_zint31.c
    # SHA-3 / SHAKE
    ../../tests/hawk-1024/sha3.c
    # NIST API wrapper (keygen / sign / verify) for HAWK-1024 (logn=10)
    ../../tests/hawk-1024/api.c
    # NIST AES-256-CTR DRBG (pure-C, no OpenSSL dependency)
    ../../tests/hawk-1024/rng.c
    # Optional keccak coprocessor
    $ASM_FILE
)

src_common=(
    ../tests/custom/common/syscalls.c
    ../tests/custom/common/crt.S
)

# ---- Compiler flags -----------------------------------------------------
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
    -I../tests/custom/env       # encoding.h  (CSR macros)
    -I../tests/custom/common    # util.h
    -I../../tests/hawk-1024     # api.h, test_vectors_1024.h, hawk headers
)

# ---- Launch simulation --------------------------------------------------
cd ./verif/sim/

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
