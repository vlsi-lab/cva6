#!/bin/bash
# ****************************************************************************
#
# Desc: Run the "rej-mldsa" SW-vs-HW test on the CVA6 simulator. Validates
#       rej_sampler.sv's new ML-DSA mode (REJ_CTRL.CAND3/RATE168/OUTWIDE)
#       against a from-scratch SHAKE128 + rej_uniform software reference.
#       See main.c's header comment for scope.
#
# Usage:
#   ./run.sh   - run from the CVA6 repository root
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
src_main=../../tests/app-tests/rej-mldsa/main.c

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
    -I../../vrf_ip/sw           # vrf_axi.h (register offsets for the AXI accelerator)
    -I../../tests/app-tests/rej-mldsa
)

# ---- Launch simulation --------------------------------------------------
cd ./verif/sim/

python3 cva6.py \
    --target=$DV_TARGET \
    --iss="$DV_SIMULATORS" \
    --iss_yaml=cva6.yaml \
    --c_tests "$src_main" \
    --sv_seed 1 \
    --gcc_opts "${src_common[*]} ${cflags[*]}" \
    --iss_timeout 7200 \
    --linker=../tests/custom/common/test.ld \
    $DV_OPTS
RC=$?

cd ../..
exit $RC
