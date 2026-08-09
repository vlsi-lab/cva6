#!/bin/bash
# ****************************************************************************
#
# Desc: Run Falcon-512 static KAT + cycle profiling on the CVA6 simulator.
#       Measures clock cycles for keygen, sign and verify using the
#       RISC-V mcycle CSR. Results are printed via the simulated UART.
#       Source: reference PQClean-style Falcon-512 implementation
#       (codec.c/common.c/fft.c/fpr.c/keygen.c/nist.c/rng.c/sign.c/vrfy.c,
#       unmodified -- no malloc/file I/O/stdio dependencies) plus a
#       bare-metal-adapted falcon512_optimized.c (tools/gen_static_test.py's auto-generated
#       driver, with printf swapped for the simulated UART and mcycle-based
#       cycle counting added).
#       SHA-3/SHAKE256 permutations (shake.c) are offloaded to the same
#       loosely-coupled Keccak AXI accelerator.
#
# Usage:
#   ./run.sh                - run keygen + sign + verify, cycle count for each
#   ./run.sh keygen         - keygen only (sign/verify skipped entirely)
#   ./run.sh sign           - sign only (keygen skipped; KAT pk/sk loaded directly)
#   ./run.sh verify         - verify only (keygen+sign skipped; KAT pk/sk/sm loaded
#                              directly) -- use this to isolate the
#                              Keccak-accelerated verify cycle count.
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
src_main=../../tests/pqc/optimized/falcon512/falcon512_optimized.c

src_incs=(
    # Falcon-512 reference implementation
    ../../tests/pqc/optimized/falcon512/codec.c
    ../../tests/pqc/optimized/falcon512/common.c
    ../../tests/pqc/optimized/falcon512/fft.c
    ../../tests/pqc/optimized/falcon512/fpr.c
    ../../tests/pqc/optimized/falcon512/keygen.c
    ../../tests/pqc/optimized/falcon512/nist.c
    ../../tests/pqc/optimized/falcon512/rng.c
    # SHA-3 / SHAKE256 (process_block offloaded to the Keccak AXI accelerator)
    ../../tests/pqc/optimized/falcon512/shake.c
    ../../tests/pqc/optimized/falcon512/sign.c
    ../../tests/pqc/optimized/falcon512/vrfy.c
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
    -I../../tests/pqc/optimized/falcon512  # api.h, uart.h, test_vectors_512.h, inner.h, fpr.h
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
