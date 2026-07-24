#!/bin/bash
# ****************************************************************************
#
# Desc: Run Falcon-512 static KAT + cycle profiling on the CVA6 simulator.
#       Measures clock cycles for keygen, sign and verify using the
#       RISC-V mcycle CSR. Results are printed via the simulated UART.
#       Source: reference PQClean-style Falcon-512 implementation
#       (codec.c/common.c/fft.c/fpr.c/keygen.c/nist.c/rng.c/shake.c/sign.c/
#       vrfy.c, unmodified -- no malloc/file I/O/stdio dependencies) plus a
#       bare-metal-adapted main.c (tools/gen_static_test.py's auto-generated
#       driver, with printf swapped for the simulated UART and mcycle-based
#       cycle counting added, same pattern as tests/hawk512/main.c).
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
src_main=../../tests/falcon512/main.c

src_incs=(
    # Falcon-512 reference implementation
    ../../tests/falcon512/codec.c
    ../../tests/falcon512/common.c
    ../../tests/falcon512/fft.c
    ../../tests/falcon512/fpr.c
    ../../tests/falcon512/keygen.c
    ../../tests/falcon512/nist.c
    ../../tests/falcon512/rng.c
    ../../tests/falcon512/shake.c
    ../../tests/falcon512/sign.c
    ../../tests/falcon512/vrfy.c
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
    -I../../tests/falcon512     # api.h, uart.h, test_vectors_512.h, inner.h, fpr.h
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
