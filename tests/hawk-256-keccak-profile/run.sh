#!/bin/bash
# ****************************************************************************
#
# Desc: Run HAWK-256 KAT + cycle profiling on the CVA6 simulator, on top of
#       the Keccak-AXI-accelerated + HW Gaussian-sampler build (same sources
#       as tests/hawk-256-keccak, plus PROF_BEGIN/END instrumentation from
#       tests/hawk-256-profiling merged in). Used to find the next-biggest
#       bottleneck in KeyGen/Verify now that SHA3/SHAKE is offloaded to HW.
#
# ****************************************************************************

# Must be run from the CVA6 repository root
source ./verif/sim/setup-env.sh

# Simulation options
export DV_OPTS="$DV_OPTS --issrun_opts=+time_out=100000000000"
DV_TARGET=cv64a6_imac_crypto
export DV_SIMULATORS=veri-testharness
unset TRACE_FAST

# Profiling level: 0=none, 1=L1 sub-functions, 2=L1+L2 sub-sub-functions
PROF_LEVEL=${PROF_LEVEL:-2}

# ---- Source files -------------------------------------------------------
src_main=../../tests/hawk-256-keccak-profile/main.c

src_incs=(
    ../../tests/hawk-256-keccak-profile/hawk_kgen.c
    ../../tests/hawk-256-keccak-profile/hawk_sign.c
    ../../tests/hawk-256-keccak-profile/hawk_vrfy.c
    ../../tests/hawk-256-keccak-profile/ng_fxp.c
    ../../tests/hawk-256-keccak-profile/ng_hawk.c
    ../../tests/hawk-256-keccak-profile/ng_mp31.c
    ../../tests/hawk-256-keccak-profile/ng_ntru.c
    ../../tests/hawk-256-keccak-profile/ng_poly.c
    ../../tests/hawk-256-keccak-profile/ng_zint31.c
    ../../tests/hawk-256-keccak-profile/sha3.c
    ../../tests/hawk-256-keccak-profile/api.c
    ../../tests/hawk-256-keccak-profile/rng.c
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
    -DPROF_LEVEL=$PROF_LEVEL
)

cflags=(
    "${cflags_opt[@]}"
    -I../tests/custom/env               # encoding.h  (CSR macros)
    -I../tests/custom/common            # util.h
    -I../../tests/hawk-256-keccak-profile  # api.h, uart.h, profiling.h, hawk headers
    -I../../keccak_ip/sw                 # keccak_axi.h (register offsets for the AXI accelerator)
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
