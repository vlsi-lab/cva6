#!/bin/bash
# ****************************************************************************
#
# Desc: Run Falcon-1024 static KAT + cycle profiling on the CVA6 simulator.
#       Measures clock cycles for keygen, sign and verify using the
#       RISC-V mcycle CSR. Results are printed via the simulated UART.
#       Source: reference PQClean-style Falcon-1024 implementation
#       (codec.c/common.c/fft.c/fpr.c/keygen.c/nist.c/rng.c/shake.c/sign.c/
#       vrfy.c, unmodified -- no malloc/file I/O/stdio dependencies) plus a
#       bare-metal-adapted main.c (tools/gen_static_test.py's auto-generated
#       driver, with printf swapped for the simulated UART and mcycle-based
#       cycle counting added, same pattern as tests/hawk1024/main.c).
#
# Usage:
#   ./run.sh                - run keygen + sign + verify, cycle count for each
#   ./run.sh keygen         - keygen only (sign/verify skipped entirely)
#   ./run.sh sign           - sign only (keygen skipped; KAT pk/sk loaded directly)
#   ./run.sh verify         - verify only (keygen+sign skipped; KAT pk/sk/sm loaded
#                              directly) -- use this to collect the reference
#                              software-only verify cycle count in isolation.
#   ./run.sh all            - explicit alias for the no-argument default
#
# ****************************************************************************

# Must be run from the CVA6 repository root
source ./verif/sim/setup-env.sh

# Simulation options
export DV_OPTS="$DV_OPTS --issrun_opts=+time_out=100000000000"
DV_TARGET=cv64a6_imac_crypto
export DV_SIMULATORS=veri-testharness
unset TRACE_FAST

# ---- Phase selection ------------------------------------------------------
RUN_KEYGEN=1
RUN_SIGN=1
RUN_VERIFY=1
case "$1" in
    keygen) RUN_SIGN=0;    RUN_VERIFY=0 ;;
    sign)   RUN_KEYGEN=0;  RUN_VERIFY=0 ;;
    verify) RUN_KEYGEN=0;  RUN_SIGN=0   ;;
    all|"") ;;
    *) echo "Usage: $0 [keygen|sign|verify|all]" >&2; exit 1 ;;
esac

# ---- Source files -------------------------------------------------------
src_main=../../tests/falcon1024/main.c

src_incs=(
    # Falcon-1024 reference implementation
    ../../tests/falcon1024/codec.c
    ../../tests/falcon1024/common.c
    ../../tests/falcon1024/fft.c
    ../../tests/falcon1024/fpr.c
    ../../tests/falcon1024/keygen.c
    ../../tests/falcon1024/nist.c
    ../../tests/falcon1024/rng.c
    ../../tests/falcon1024/shake.c
    ../../tests/falcon1024/sign.c
    ../../tests/falcon1024/vrfy.c
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
    -DRUN_KEYGEN=$RUN_KEYGEN
    -DRUN_SIGN=$RUN_SIGN
    -DRUN_VERIFY=$RUN_VERIFY
)

cflags=(
    "${cflags_opt[@]}"
    -I../tests/custom/env       # encoding.h  (CSR macros)
    -I../tests/custom/common    # util.h
    -I../../tests/falcon1024    # api.h, uart.h, test_vectors_1024.h, inner.h, fpr.h
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
