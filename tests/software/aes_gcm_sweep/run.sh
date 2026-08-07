#!/bin/bash

# Source environment setup
source ./verif/sim/setup-env.sh

DV_TARGET=cv64a6_imafdc_sv39
export DV_SIMULATORS=veri-testharness
export TRACE_FAST=1

cd ./verif/sim

src_main=../../tests/software/aes_gcm_sweep/aes_gcm_sweep.c

src_common=(
    ../tests/custom/common/syscalls.c
    ../tests/custom/common/crt.S
    ../../tests/software/common/aes_gcm.c
    ../../tests/software/common/ghash.c
)

cflags=(
    -O2 -g
    -fno-tree-loop-distribute-patterns
    -static
    -mcmodel=medany
    -fvisibility=hidden
    -nostartfiles
    -lgcc

    -I../tests/custom/env
    -I../tests/custom/common
    -I../../tests/software/common
)

# Software GCM at up to 1024 B payload is GHASH-dominated and needs well
# above the simulator's default ~2,000,000-cycle watchdog
# (corev_apu/tb/rvfi_tracer.sv's `+time_out` plusarg, default 2000000) --
# 20,000,000 gives a large margin over this sweep's actual cost. Separately,
# cva6.py's own --iss_timeout is a wall-clock (not simulated-cycle) Python
# subprocess timeout, default 500s -- observed to be the actual blocker on
# a first run (measured ~1000-2500 simulated cycles/sec on this machine, so
# 500s covers only ~1 of this sweep's 4 sizes); raised well above the
# sweep's expected wall-clock cost.
python3 cva6.py \
    --target=$DV_TARGET \
    --iss="$DV_SIMULATORS" \
    --iss_yaml=cva6.yaml \
    --issrun_opts "+debug_disable=1 +time_out=20000000" \
    --iss_timeout 7200 \
    --c_tests "$src_main" \
    --gcc_opts "${src_common[*]} ${cflags[*]}" \
    --linker=../tests/custom/common/test.ld
RESULT=$?

cd ../..
exit $RESULT
