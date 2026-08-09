#!/bin/bash
# ****************************************************************************
#
# Desc: Run Falcon-512 verify-only KAT + cycle/instruction profiling on the
#       CVA6 simulator. vrf_ip is a verify-only accelerator, so this harness
#       only exercises crypto_sign_open() -- keygen/sign are not run (see
#       tests/pqc/ for the full keygen+sign+verify baseline/optimized
#       harness). Measures clock cycles (mcycle) and retired instructions
#       (minstret). Results are printed via the simulated UART.
#       Source: reference PQClean-style Falcon-512 implementation
#       (codec.c/common.c/fft.c/fpr.c/keygen.c/nist.c/rng.c/sign.c/vrfy.c,
#       unmodified -- no malloc/file I/O/stdio dependencies) plus
#       falcon512_optimized.c, trimmed to verify-only.
#       SHA-3/SHAKE256 permutations (shake.c) are offloaded to the shared
#       vrf_ip Keccak AXI accelerator.
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
src_main=../../tests/vrf/optimized/falcon512/falcon512_optimized.c

src_incs=(
    # Falcon-512 reference implementation
    ../../tests/vrf/optimized/falcon512/codec.c
    ../../tests/vrf/optimized/falcon512/common.c
    ../../tests/vrf/optimized/falcon512/fft.c
    ../../tests/vrf/optimized/falcon512/fpr.c
    ../../tests/vrf/optimized/falcon512/keygen.c
    ../../tests/vrf/optimized/falcon512/nist.c
    ../../tests/vrf/optimized/falcon512/rng.c
    # SHA-3 / SHAKE256 (process_block offloaded to the vrf_ip Keccak AXI accelerator)
    ../../tests/vrf/optimized/falcon512/shake.c
    ../../tests/vrf/optimized/falcon512/sign.c
    ../../tests/vrf/optimized/falcon512/vrfy.c
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
    -I../../tests/vrf/optimized/falcon512  # api.h, uart.h, test_vectors_512.h, inner.h, fpr.h
    -I../../vrf_ip/sw        # vrf_axi.h (register offsets for the AXI accelerator)
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
