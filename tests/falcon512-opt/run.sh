#!/bin/bash
# ****************************************************************************
#
# Desc: Run Falcon-512 static KAT + cycle profiling on the CVA6 simulator.
#       Measures clock cycles for keygen, sign and verify using the
#       RISC-V mcycle CSR. Results are printed via the simulated UART.
#       Source: reference PQClean-style Falcon-512 implementation
#       (codec.c/common.c/fft.c/fpr.c/keygen.c/nist.c/rng.c/sign.c/vrfy.c,
#       unmodified -- no malloc/file I/O/stdio dependencies) plus a
#       bare-metal-adapted main.c (tools/gen_static_test.py's auto-generated
#       driver, with printf swapped for the simulated UART and mcycle-based
#       cycle counting added, same pattern as tests/hawk512/main.c).
#       SHA-3/SHAKE256 permutations (shake.c) are offloaded to the same
#       loosely-coupled Keccak AXI accelerator used by tests/hawk1024-opt.
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
src_main=../../tests/falcon512-opt/main.c

src_incs=(
    # Falcon-512 reference implementation
    ../../tests/falcon512-opt/codec.c
    ../../tests/falcon512-opt/common.c
    ../../tests/falcon512-opt/fft.c
    ../../tests/falcon512-opt/fpr.c
    ../../tests/falcon512-opt/keygen.c
    ../../tests/falcon512-opt/nist.c
    ../../tests/falcon512-opt/rng.c
    # SHA-3 / SHAKE256 (process_block offloaded to the Keccak AXI accelerator)
    ../../tests/falcon512-opt/shake.c
    ../../tests/falcon512-opt/sign.c
    ../../tests/falcon512-opt/vrfy.c
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
    -I../../tests/falcon512-opt  # api.h, uart.h, test_vectors_512.h, inner.h, fpr.h
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
