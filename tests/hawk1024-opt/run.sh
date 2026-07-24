#!/bin/bash
# ****************************************************************************
#
# Auth: Alessandra Dolmeta - Politecnico di Torino
# Date: June 2025
# Desc: Run HAWK-1024 KAT + cycle profiling on the CVA6 simulator.
#       Measures clock cycles for keygen, sign and verify using the
#       RISC-V mcycle CSR. Results are printed via the simulated UART.
#       SHA-3/SHAKE permutations are offloaded to the loosely-coupled
#       Keccak AXI accelerator instead of the software process_block().
#
# ****************************************************************************

# Must be run from the CVA6 repository root
source ./verif/sim/setup-env.sh

# Simulation options
export DV_OPTS="$DV_OPTS --issrun_opts=+time_out=100000000000"
DV_TARGET=cv64a6_imac_crypto
export DV_SIMULATORS=veri-testharness
unset TRACE_FAST

# ---- Source files -------------------------------------------------------
src_main=../../tests/hawk1024-opt/main.c

src_incs=(
    # HAWK core implementation
    ../../tests/hawk1024-opt/hawk_kgen.c
    ../../tests/hawk1024-opt/hawk_sign.c
    ../../tests/hawk1024-opt/hawk_vrfy.c
    # NTT / polynomial helpers
    ../../tests/hawk1024-opt/ng_fxp.c
    ../../tests/hawk1024-opt/ng_hawk.c
    ../../tests/hawk1024-opt/ng_mp31.c
    ../../tests/hawk1024-opt/ng_ntru.c
    ../../tests/hawk1024-opt/ng_poly.c
    ../../tests/hawk1024-opt/ng_zint31.c
    # SHA-3 / SHAKE (process_block offloaded to the Keccak AXI accelerator)
    ../../tests/hawk1024-opt/sha3.c
    # NIST API wrapper (keygen / sign / verify) for HAWK-1024 (logn=10)
    ../../tests/hawk1024-opt/api.c
    # NIST AES-256-CTR DRBG (pure-C, no OpenSSL dependency)
    ../../tests/hawk1024-opt/rng.c
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
)

cflags=(
    "${cflags_opt[@]}"
    -I../tests/custom/env       # encoding.h  (CSR macros)
    -I../tests/custom/common    # util.h
    -I../../tests/hawk1024-opt      # api.h, uart.h, test_vectors_1024.h, hawk headers
    -I../../keccak_ip/sw        # keccak_axi.h (register offsets for the AXI accelerator)
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
