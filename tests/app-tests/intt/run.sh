#!/bin/bash
# ****************************************************************************
#
# Desc: Run the "intt" SW-vs-HW microbenchmark on the CVA6 simulator.
#       Compares Falcon's software inverse NTT (mod 12289, n=512) against
#       the vrf_ip AXI accelerator's ntt_engine.sv offload
#       (mq_iNTT_hw()/fmp_NTT_hw(), extracted from
#       tests/pqc/optimized/falcon512/vrfy.c), measuring clock cycles via
#       the RISC-V mcycle CSR and comparing outputs element-wise.
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
src_main=../../tests/app-tests/intt/intt.c

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
    --gcc_opts "${src_common[*]} ${cflags[*]}" \
    --iss_timeout 7200 \
    --linker=../tests/custom/common/test.ld \
    $DV_OPTS
RC=$?

cd ../..
exit $RC
