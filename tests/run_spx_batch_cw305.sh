#!/bin/bash
# =============================================================================
# tests/run_spx_batch_cw305.sh - Batch driver for SLH-DSA SPHINCS+ simulations
# using the CW305-style compilation flags (rv64imac/lp64, -Os, CW305 runtime).
#
# Same CLI as run_spx_batch.sh.  Differences vs. that script:
#   * -march=rv64imac_zicsr_zifencei -mabi=lp64      (soft-float, no F/D regs)
#   * -Os -ffunction-sections -fdata-sections
#     -fno-asynchronous-unwind-tables -fno-unwind-tables
#   * -Wall -Wno-comment -Wno-unused-variable -Wno-unused-function
#   * Defines: -DSPX_CW305 -DSPX_CW305_SHAKE -DSPX_CW305_TEST_NAME="<variant>"
#   * Uses verif/tests/custom/common/cw305_crt.S      (instead of crt.S)
#   * Uses verif/tests/custom/common/cw305_linker.ld  (instead of test.ld)
#
# Phase selection is still done via the existing main.c macros
# (TEST_KEY / TEST_SIGN / TEST_SIGN_OPEN), so no extra source files are needed.
#
# Usage:
#     bash tests/run_spx_batch_cw305.sh [options] PHASE [PHASE ...]
# See `--help` for the full option list.
# =============================================================================

set -o pipefail

_die() { echo "Error: $*" >&2; exit 1; }

_usage() {
    sed -n '2,/^# ===/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' | head -n 40
}

# --- locate repo ------------------------------------------------------------

THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TESTS_DIR="$THIS_DIR"
REPO_ROOT="$(cd "$TESTS_DIR/.." && pwd)"
SIM_DIR="$REPO_ROOT/verif/sim"
CW305_CRT="../tests/custom/common/cw305_crt.S"
CW305_LD="../tests/custom/common/cw305_linker.ld"

[[ -d "$SIM_DIR" ]] || _die "cannot find $SIM_DIR"
[[ -f "$REPO_ROOT/verif/tests/custom/common/cw305_crt.S"     ]] || _die "missing cw305_crt.S"
[[ -f "$REPO_ROOT/verif/tests/custom/common/cw305_linker.ld" ]] || _die "missing cw305_linker.ld"

# --- defaults ---------------------------------------------------------------

MODE="baseline"
DEFAULT_VARIANTS=(
    SPHINCS-128f-robust
    SPHINCS-128f-simple
    SPHINCS-192f-robust
    SPHINCS-192f-simple
    SPHINCS-256f-robust
    SPHINCS-256f-simple
)
VARIANTS=()
PHASES=()
RESULTS_DIR=""

# --- argument parsing -------------------------------------------------------

while (( $# > 0 )); do
    case "$1" in
        -h|--help)             _usage; exit 0 ;;
        --mode)                [[ $# -ge 2 ]] || _die "--mode requires an argument"; MODE="$2"; shift 2 ;;
        --mode=*)              MODE="${1#*=}"; shift ;;
        --variants)            [[ $# -ge 2 ]] || _die "--variants requires an argument"; read -r -a VARIANTS <<<"$2"; shift 2 ;;
        --variants=*)          read -r -a VARIANTS <<<"${1#*=}"; shift ;;
        --results-dir)         [[ $# -ge 2 ]] || _die "--results-dir requires an argument"; RESULTS_DIR="$2"; shift 2 ;;
        --results-dir=*)       RESULTS_DIR="${1#*=}"; shift ;;
        keygen|sign|verify)    PHASES+=("$1"); shift ;;
        all)                   PHASES+=(keygen sign verify); shift ;;
        --)                    shift; break ;;
        -*)                    _die "unknown option: $1" ;;
        *)                     _die "unknown argument: $1" ;;
    esac
done

(( ${#PHASES[@]} > 0 )) || _die "no phases specified (keygen|sign|verify|all)"
case "$MODE" in baseline|optimized|all) ;; *) _die "invalid --mode '$MODE'";; esac
(( ${#VARIANTS[@]} == 0 )) && VARIANTS=("${DEFAULT_VARIANTS[@]}")

MODES=()
[[ "$MODE" == "baseline"  || "$MODE" == "all" ]] && MODES+=(baseline)
[[ "$MODE" == "optimized" || "$MODE" == "all" ]] && MODES+=(optimized)

TS="$(date +%Y%m%d_%H%M%S)"
[[ -z "$RESULTS_DIR" ]] && RESULTS_DIR="$TESTS_DIR/results/spx_batch_cw305_$TS"
mkdir -p "$RESULTS_DIR" || _die "cannot create results dir: $RESULTS_DIR"

SUMMARY="$RESULTS_DIR/summary.tsv"
printf 'mode\tvariant\tphase\tstatus\tduration_s\tlog\n' > "$SUMMARY"

# --- per-phase defines ------------------------------------------------------

phase_defines() {
    case "$1" in
        keygen) echo "-DTEST_KEY=1 -DTEST_SIGN=0 -DTEST_SIGN_OPEN=0" ;;
        sign)   echo "-DTEST_KEY=0 -DTEST_SIGN=1 -DTEST_SIGN_OPEN=0" ;;
        verify) echo "-DTEST_KEY=0 -DTEST_SIGN=0 -DTEST_SIGN_OPEN=1" ;;
        *) return 1 ;;
    esac
}

# --- per-variant simulation -------------------------------------------------

run_one() {
    local mode="$1" variant="$2" phase="$3"
    local tag="${mode}-${variant}-${phase}-cw305"
    local dest_log="$RESULTS_DIR/${tag}.log.iss"

    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "▶ ${tag}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    local test_dir_abs="$TESTS_DIR/pqc/$mode/DS/SLH-DSA/$variant"
    [[ -d "$test_dir_abs" ]] || { echo "  ! missing test dir: $test_dir_abs"; return 2; }

    local thash_file
    if [[ "$variant" == *-robust ]]; then thash_file="thash_shake_robust.c"
    else                                  thash_file="thash_shake_simple.c"
    fi

    local src_base="$test_dir_abs"
    [[ -f "$test_dir_abs/src/address.c" ]] && src_base="$test_dir_abs/src"

    local test_dir_rel="../../tests/pqc/$mode/DS/SLH-DSA/$variant"
    local src_base_rel
    if [[ "$src_base" == "$test_dir_abs/src" ]]; then
        src_base_rel="$test_dir_rel/src"
    else
        src_base_rel="$test_dir_rel"
    fi

    local src_main="$test_dir_rel/main.c"
    local src_incs=(
        "$src_base_rel/address.c"
        "$src_base_rel/fips202.c"
        "$src_base_rel/fors.c"
        "$src_base_rel/hash_shake.c"
        "$src_base_rel/merkle.c"
        "$src_base_rel/randombytes.c"
        "$src_base_rel/sign.c"
        "$src_base_rel/$thash_file"
        "$src_base_rel/utils.c"
        "$src_base_rel/utilsx1.c"
        "$src_base_rel/wots.c"
        "$src_base_rel/wotsx1.c"
    )
    if [[ "$mode" == "optimized" ]]; then
        src_incs+=("$src_base_rel/keccak_coproc.S")
    fi

    # CW305 runtime crt instead of generic crt
    local src_common=(
        ../tests/custom/common/syscalls.c
        "$CW305_CRT"
    )

    # CW305 cflags
    local cflags_cw305=(
        -Wall -Wno-comment -Wno-unused-variable -Wno-unused-function
        -static -mcmodel=medany -fvisibility=hidden
        -Os -ffunction-sections -fdata-sections
        -fno-asynchronous-unwind-tables -fno-unwind-tables
        -nostartfiles -g
        -march=rv64imac_zicsr_zifencei -mabi=lp64
        -DSPX_CW305 -DSPX_CW305_SHAKE
        "-DSPX_CW305_TEST_NAME=\"$variant\""
    )

    local phase_def
    phase_def="$(phase_defines "$phase")" || { echo "  ! bad phase '$phase'"; return 2; }

    local cflags=(
        "${cflags_cw305[@]}"
        $phase_def
        -I../tests/custom/env
        -I../tests/custom/common
        -I"$test_dir_rel"
        -I"$test_dir_rel/src"
        -I"$test_dir_rel/include"
        -I../../tests/inc
        -I../../tests
        -Wl,--gc-sections
        -lgcc
    )

    : "${LD_LIBRARY_PATH:=}"; export LD_LIBRARY_PATH
    cd "$REPO_ROOT" || { echo "  ! cannot cd $REPO_ROOT"; return 2; }
    [[ -f ./verif/sim/setup-env.sh ]] || { echo "  ! missing ./verif/sim/setup-env.sh"; return 2; }
    # shellcheck disable=SC1091
    source ./verif/sim/setup-env.sh >/dev/null || { echo "  ! setup-env.sh failed"; return 2; }

    local TEST_TIMEOUT="${HASH_TEST_TIMEOUT:-100000000000}"
    local ISS_TIMEOUT="${HASH_ISS_TIMEOUT:-1000000}"
    local DV_TARGET=cv64a6_imafdc_sv39
    local DV_SIMULATORS="${DV_SIMULATORS:-veri-testharness}"
    local DV_OPTS_LOCAL="${DV_OPTS:-} --issrun_opts=+time_out=${TEST_TIMEOUT}"
    unset TRACE_FAST

    local PYTHON=python3
    command -v python3.9 >/dev/null 2>&1 && PYTHON=python3.9

    cd "$SIM_DIR" || { echo "  ! cannot cd $SIM_DIR"; return 2; }

    local started; started="$(date +%s)"

    set -x
    "$PYTHON" cva6.py \
        --target="$DV_TARGET" \
        --iss="$DV_SIMULATORS" \
        --iss_yaml=cva6.yaml \
        --c_tests "$src_main" \
        --sv_seed 1 \
        --gcc_opts "${src_incs[*]} ${src_common[*]} ${cflags[*]}" \
        --iss_timeout "$ISS_TIMEOUT" \
        --linker="$CW305_LD" \
        $DV_OPTS_LOCAL
    local rc=$?
    set +x

    local ended; ended="$(date +%s)"
    local dur=$(( ended - started ))

    local found=""
    while IFS= read -r f; do
        if [[ -n "$f" ]]; then
            local mt; mt="$(stat -c %Y "$f" 2>/dev/null || echo 0)"
            if (( mt >= started - 5 )); then
                found="$f"
                break
            fi
        fi
    done < <(find "$SIM_DIR"/out_* -maxdepth 2 -type f \
                   -name "main.${DV_TARGET}.log.iss" 2>/dev/null \
                   -printf '%T@\t%p\n' | sort -rn | cut -f2-)

    if [[ -z "$found" ]]; then
        found="$(find "$SIM_DIR"/out_* -maxdepth 2 -type f \
                       -name "main.${DV_TARGET}.log.iss" 2>/dev/null \
                       -printf '%T@\t%p\n' | sort -rn | head -1 | cut -f2-)"
    fi

    local status log_path="-"
    if [[ -n "$found" && -f "$found" ]]; then
        if mv -f "$found" "$dest_log" 2>/dev/null; then
            log_path="$dest_log"
        elif cp -f "$found" "$dest_log" 2>/dev/null; then
            log_path="$dest_log"
        fi
    fi

    if (( rc == 0 )) && [[ -f "$dest_log" ]]; then
        status="OK"
        echo "  ✓ $tag  (${dur}s) -> $dest_log"
    elif (( rc == 0 )); then
        status="OK_NOLOG"
        echo "  ! $tag  (${dur}s) finished but log not found"
    else
        status="FAIL($rc)"
        echo "  ✗ $tag  (${dur}s) cva6.py exit=$rc"
    fi

    printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$mode" "$variant" "$phase" "$status" "$dur" "$log_path" >> "$SUMMARY"
    return 0
}

# --- main loop --------------------------------------------------------------

echo
echo "╔════════════════════════════════════════════════════════╗"
echo "║   SLH-DSA SPHINCS+ Batch Driver  [CW305 build flags]   ║"
echo "╚════════════════════════════════════════════════════════╝"
echo "Modes    : ${MODES[*]}"
echo "Variants : ${VARIANTS[*]}"
echo "Phases   : ${PHASES[*]}"
echo "Results  : $RESULTS_DIR"
echo "Summary  : $SUMMARY"

total=$(( ${#MODES[@]} * ${#VARIANTS[@]} * ${#PHASES[@]} ))
echo "Total simulations: $total"

idx=0
for m in "${MODES[@]}"; do
    for v in "${VARIANTS[@]}"; do
        for p in "${PHASES[@]}"; do
            idx=$(( idx + 1 ))
            echo
            echo "############ [$idx/$total] $m / $v / $p ############"
            run_one "$m" "$v" "$p" || echo "  (run_one returned non-zero; continuing)"
        done
    done
done

echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "All done. Summary:"
column -t -s $'\t' "$SUMMARY" 2>/dev/null || cat "$SUMMARY"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
