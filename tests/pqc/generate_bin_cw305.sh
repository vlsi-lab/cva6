#!/usr/bin/env bash
# CW305-style build of PQC .bin files. Same CLI as generate_bin.sh, but with:
#   -march=rv64imac_zicsr_zifencei -mabi=lp64
#   -Os, function/data sections, no unwind tables
#   -DSPX_CW305 -DSPX_CW305_SHAKE -DSPX_CW305_TEST_NAME="<variant>"
#   uses cw305_crt.S and cw305_linker.ld instead of crt.S / test.ld

set -uo pipefail

usage() {
  cat <<'EOF'
Usage:
  tests/pqc/generate_bin_cw305.sh [options] [FOLDER_NAME]

Generate raw .bin files for PQC folders with CW305 build flags.

Options:
  -v, --variant <baseline|optimized|all>  Variant selection (default: all)
  -n, --name <FOLDER_NAME|all>            Filter by folder basename (default: all)
  -t, --test <auto|keygen|sign|sign-open> Test mode override (default: auto)
      --test-keygen / --test-sign / --test-sign-open
  -o, --out <path>                        Output root (default: tests/pqc/generated_bin_cw305)
      --clean                              Remove all .bin files under output root and exit
  -h, --help                              Show this help
EOF
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

VARIANT="all"; FOLDER_NAME="all"; TEST_MODE="auto"; CLEAN_ONLY=0
OUT_ROOT="$REPO_ROOT/tests/pqc/generated_bin_cw305"

while [[ $# -gt 0 ]]; do
  case "$1" in
    -v|--variant)         VARIANT="$2"; shift 2 ;;
    -n|--name)            FOLDER_NAME="$2"; shift 2 ;;
    -t|--test)            TEST_MODE="$2"; shift 2 ;;
    --test-keygen)        TEST_MODE="keygen"; shift ;;
    --test-sign)          TEST_MODE="sign"; shift ;;
    --test-sign-open)     TEST_MODE="sign-open"; shift ;;
    -o|--out)
      if [[ "$2" = /* ]]; then OUT_ROOT="$2"; else OUT_ROOT="$REPO_ROOT/$2"; fi
      shift 2 ;;
    --clean)              CLEAN_ONLY=1; shift ;;
    -h|--help)            usage; exit 0 ;;
    --)                   shift; break ;;
    -* )                  echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
    *)                    FOLDER_NAME="$1"; shift ;;
  esac
done

[[ "$VARIANT" =~ ^(all|baseline|optimized)$ ]] || { echo "Invalid variant: $VARIANT" >&2; exit 1; }
[[ "$TEST_MODE" =~ ^(auto|keygen|sign|sign-open)$ ]] || { echo "Invalid test mode: $TEST_MODE" >&2; exit 1; }

if [[ $CLEAN_ONLY -eq 1 ]]; then
  [[ -d "$OUT_ROOT" ]] || { echo "No output directory to clean: $OUT_ROOT"; exit 0; }
  bin_count="$(find "$OUT_ROOT" -type f -name '*.bin' | wc -l)"
  if [[ "$bin_count" -eq 0 ]]; then echo "No .bin files found under: $OUT_ROOT"; exit 0; fi
  find "$OUT_ROOT" -type f -name '*.bin' -delete
  echo "Removed $bin_count .bin file(s) under: $OUT_ROOT"; exit 0
fi

mkdir -p "$OUT_ROOT"
cd "$REPO_ROOT" || exit 1

[[ -f ./verif/sim/setup-env.sh                    ]] || { echo "Error: missing ./verif/sim/setup-env.sh" >&2; exit 1; }
[[ -f ./verif/tests/custom/common/cw305_crt.S     ]] || { echo "Error: missing cw305_crt.S" >&2; exit 1; }
[[ -f ./verif/tests/custom/common/cw305_linker.ld ]] || { echo "Error: missing cw305_linker.ld" >&2; exit 1; }

: "${LD_LIBRARY_PATH:=}"
# shellcheck disable=SC1091
set +u; source ./verif/sim/setup-env.sh; set -u

if [[ -z "${RISCV_CC:-}" || -z "${RISCV_OBJCOPY:-}" ]]; then
  echo "Error: RISCV_CC/RISCV_OBJCOPY are not set after setup-env.sh" >&2; exit 1
fi

MARCH_DEFAULT="rv64imac_zicsr_zifencei"
MABI_DEFAULT="lp64"
MARCH="${PQC_MARCH:-$MARCH_DEFAULT}"
MABI="${PQC_MABI:-$MABI_DEFAULT}"

variants=()
if [[ "$VARIANT" = "all" ]]; then variants=(baseline optimized); else variants=("$VARIANT"); fi

BUILD_DIR="$(mktemp -d "$REPO_ROOT/verif/sim/.pqc_bin_cw305_build.XXXXXX")"
trap 'rm -rf "$BUILD_DIR"' EXIT

found_any=0; built_count=0; fail_count=0

compile_one() {
  local variant_name="$1" rel_from_pqc="$2"
  local test_dir="../../tests/pqc/$rel_from_pqc"
  local test_name src_base thash_file elf bin bin_name

  test_name="$(basename "$rel_from_pqc")"

  [[ -f "$test_dir/main.c" ]] || { echo "[skip] missing main.c: $rel_from_pqc"; return; }

  src_base="$test_dir"
  [[ -f "$test_dir/src/address.c" ]] && src_base="$test_dir/src"

  thash_file=""
  if   [[ -f "$src_base/thash_shake_robust.c" ]]; then thash_file="$src_base/thash_shake_robust.c"
  elif [[ -f "$src_base/thash_shake_simple.c" ]]; then thash_file="$src_base/thash_shake_simple.c"
  fi
  [[ -n "$thash_file" ]] || { echo "[skip] missing thash source in: $rel_from_pqc"; return; }

  local -a src_incs=(
    "$src_base/address.c"
    "$src_base/fips202.c"
    "$src_base/fors.c"
    "$src_base/hash_shake.c"
    "$src_base/merkle.c"
    "$src_base/randombytes.c"
    "$src_base/sign.c"
    "$thash_file"
    "$src_base/utils.c"
    "$src_base/utilsx1.c"
    "$src_base/wots.c"
    "$src_base/wotsx1.c"
  )
  if [[ "$variant_name" = "optimized" && -f "$src_base/keccak_coproc.S" ]]; then
    src_incs+=("$src_base/keccak_coproc.S")
  fi

  local -a src_common=(
    ../tests/custom/common/syscalls.c
    ../tests/custom/common/cw305_crt.S
  )

  local -a cflags=(
    -Wall -Wno-comment -Wno-unused-variable -Wno-unused-function
    -static -mcmodel=medany -fvisibility=hidden
    -Os -ffunction-sections -fdata-sections
    -fno-asynchronous-unwind-tables -fno-unwind-tables
    -nostartfiles -g
    -lgcc -Wl,--gc-sections
    -DSPX_CW305 -DSPX_CW305_SHAKE
    "-DSPX_CW305_TEST_NAME=\"$test_name\""
    -I../tests/custom/env
    -I../tests/custom/common
    -I"$test_dir"
  )
  [[ -d "$test_dir/src"     ]] && cflags+=("-I$test_dir/src")
  [[ -d "$test_dir/include" ]] && cflags+=("-I$test_dir/include")
  cflags+=( -I../../tests/inc -I../../tests )

  local -a test_defines=()
  case "$TEST_MODE" in
    keygen)    test_defines=(-DTEST_KEY=1 -DTEST_SIGN=0 -DTEST_SIGN_OPEN=0) ;;
    sign)      test_defines=(-DTEST_KEY=0 -DTEST_SIGN=1 -DTEST_SIGN_OPEN=0) ;;
    sign-open) test_defines=(-DTEST_KEY=0 -DTEST_SIGN=0 -DTEST_SIGN_OPEN=1) ;;
    auto)      ;;
  esac

  local out_test_dir="$OUT_ROOT/$variant_name"
  mkdir -p "$out_test_dir"

  elf="$BUILD_DIR/${variant_name}_${test_name}.elf"
  if [[ "$TEST_MODE" = "auto" ]]; then
    bin_name="${test_name}.bin"
  else
    bin_name="${test_name}-test-${TEST_MODE}.bin"
  fi
  bin="$out_test_dir/${bin_name}"

  if ! "$RISCV_CC" \
    "$test_dir/main.c" \
    "${src_incs[@]}" \
    "${src_common[@]}" \
    "${cflags[@]}" \
    "${test_defines[@]}" \
    -T../tests/custom/common/cw305_linker.ld \
    -march="$MARCH" \
    -mabi="$MABI" \
    -o "$elf"; then
    fail_count=$((fail_count + 1))
    echo "[fail] compile failed: $rel_from_pqc" >&2; return
  fi

  if ! "$RISCV_OBJCOPY" -O binary "$elf" "$bin"; then
    fail_count=$((fail_count + 1))
    echo "[fail] objcopy failed: $rel_from_pqc" >&2; return
  fi

  built_count=$((built_count + 1))
  echo "[ok] $rel_from_pqc -> $bin"
}

cd "$REPO_ROOT/verif/sim" || exit 1

for v in "${variants[@]}"; do
  base_dir="$REPO_ROOT/tests/pqc/$v"
  [[ -d "$base_dir" ]] || continue
  while IFS= read -r run_sh; do
    found_any=1
    rel_dir="${run_sh#"$REPO_ROOT/tests/pqc/"}"
    rel_dir="$(dirname "$rel_dir")"
    if [[ "$FOLDER_NAME" != "all" && "$(basename "$rel_dir")" != "$FOLDER_NAME" ]]; then
      continue
    fi
    compile_one "$v" "$rel_dir"
  done < <(find "$base_dir" -type f -name run.sh | sort)
done

if [[ $found_any -eq 0 ]]; then echo "No PQC run.sh scripts found under tests/pqc." >&2; exit 1; fi
if [[ $built_count -eq 0 ]]; then echo "No matching folders were built. Check --name/--variant filters." >&2; exit 1; fi
if [[ $fail_count -gt 0 ]]; then
  echo; echo "Completed with $fail_count failure(s) and $built_count success(es)." >&2; exit 1
fi

echo
echo "Generated $built_count bin file(s) under: $OUT_ROOT"
