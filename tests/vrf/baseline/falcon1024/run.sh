#!/bin/bash
# ****************************************************************************
#
# Desc: Run Falcon-1024 verify-only KAT + cycle/instruction profiling on the
#       CVA6 simulator. vrf_ip is a verify-only accelerator, so this harness
#       only exercises crypto_sign_open() -- keygen/sign are not run (see
#       tests/pqc/ for the full keygen+sign+verify baseline/optimized
#       harness). Measures clock cycles (mcycle) and retired instructions
#       (minstret). Results are printed via the simulated UART.
#       Source: reference PQClean-style Falcon-1024 implementation
#       (codec.c/common.c/fft.c/fpr.c/keygen.c/nist.c/rng.c/shake.c/sign.c/
#       vrfy.c, unmodified -- no malloc/file I/O/stdio dependencies) plus
#       falcon1024_baseline.c, trimmed to verify-only.
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
src_main=../../tests/vrf/baseline/falcon1024/falcon1024_baseline.c

src_incs=(
    # Falcon-1024 reference implementation
    ../../tests/vrf/baseline/falcon1024/codec.c
    ../../tests/vrf/baseline/falcon1024/common.c
    ../../tests/vrf/baseline/falcon1024/fft.c
    ../../tests/vrf/baseline/falcon1024/fpr.c
    ../../tests/vrf/baseline/falcon1024/keygen.c
    ../../tests/vrf/baseline/falcon1024/nist.c
    ../../tests/vrf/baseline/falcon1024/rng.c
    ../../tests/vrf/baseline/falcon1024/shake.c
    ../../tests/vrf/baseline/falcon1024/sign.c
    ../../tests/vrf/baseline/falcon1024/vrfy.c
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
    -I../../tests/vrf/baseline/falcon1024    # api.h, uart.h, test_vectors_1024.h, inner.h, fpr.h
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
    --iss_timeout 7200 \
    --linker=../tests/custom/common/test.ld \
    $DV_OPTS

cd ../..
