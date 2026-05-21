#!/usr/bin/env bash

set -uo pipefail

usage() {
  cat <<'EOF'
Usage:
  tests/pqc/generate_elf.sh [options] [FOLDER_NAME]

Generate RISC-V .elf files for PQC folders without running ISS/simulation.

The script keeps running even if one folder fails to compile, and reports
all failures at the end.

Options:
  -v, --variant <baseline|optimized|all>  Variant selection (default: all)
  -n, --name <FOLDER_NAME|all>            Filter by folder basename (default: all)
  -t, --test <auto|keygen|sign|sign-open> Test mode override (default: auto)
      --test-keygen                        Shortcut for --test keygen
      --test-sign                          Shortcut for --test sign
      --test-sign-open                     Shortcut for --test sign-open
  -o, --out <path>                        Output root (default: tests/pqc/generated_elf)
      --clean                              Remove all .elf files under output root and exit
  -h, --help                              Show this help

Examples:
  tests/pqc/generate_elf.sh
  tests/pqc/generate_elf.sh --variant optimized
  tests/pqc/generate_elf.sh --name SPHINCS-128f-robust
  tests/pqc/generate_elf.sh SPHINCS-256f-simple
  tests/pqc/generate_elf.sh --test keygen
  tests/pqc/generate_elf.sh --variant baseline --test-sign-open
  tests/pqc/generate_elf.sh --clean
EOF
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

VARIANT="all"
FOLDER_NAME="all"
TEST_MODE="auto"
OUT_ROOT="$REPO_ROOT/tests/pqc/generated_elf"
CLEAN_ONLY=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    -v|--variant)
      VARIANT="$2"
      shift 2
      ;;
    -n|--name)
      FOLDER_NAME="$2"
      shift 2
      ;;
    -t|--test)
      TEST_MODE="$2"
      shift 2
      ;;
    --test-keygen)
      TEST_MODE="keygen"
      shift
      ;;
    --test-sign)
      TEST_MODE="sign"
      shift
      ;;
    --test-sign-open)
      TEST_MODE="sign-open"
      shift
      ;;
    -o|--out)
      if [[ "$2" = /* ]]; then
        OUT_ROOT="$2"
      else
        OUT_ROOT="$REPO_ROOT/$2"
      fi
      shift 2
      ;;
    --clean)
      CLEAN_ONLY=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    -* )
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
    *)
      # Positional shorthand: folder basename
      FOLDER_NAME="$1"
      shift
      ;;
  esac
done

if [[ "$VARIANT" != "all" && "$VARIANT" != "baseline" && "$VARIANT" != "optimized" ]]; then
  echo "Invalid variant: $VARIANT" >&2
  exit 1
fi

if [[ "$TEST_MODE" != "auto" && "$TEST_MODE" != "keygen" && "$TEST_MODE" != "sign" && "$TEST_MODE" != "sign-open" ]]; then
  echo "Invalid test mode: $TEST_MODE" >&2
  exit 1
fi

if [[ $CLEAN_ONLY -eq 1 ]]; then
  if [[ ! -d "$OUT_ROOT" ]]; then
    echo "No output directory to clean: $OUT_ROOT"
    exit 0
  fi

  elf_count="$(find "$OUT_ROOT" -type f -name '*.elf' | wc -l)"
  if [[ "$elf_count" -eq 0 ]]; then
    echo "No .elf files found under: $OUT_ROOT"
    exit 0
  fi

  find "$OUT_ROOT" -type f -name '*.elf' -delete
  echo "Removed $elf_count .elf file(s) under: $OUT_ROOT"
  exit 0
fi

mkdir -p "$OUT_ROOT"

cd "$REPO_ROOT" || exit 1

if [[ ! -f ./verif/sim/setup-env.sh ]]; then
  echo "Error: missing ./verif/sim/setup-env.sh" >&2
  exit 1
fi

# setup-env.sh may reference LD_LIBRARY_PATH directly.
: "${LD_LIBRARY_PATH:=}"

# shellcheck disable=SC1091
set +u
source ./verif/sim/setup-env.sh
set -u

if [[ -z "${RISCV_CC:-}" ]]; then
  echo "Error: RISCV_CC is not set after setup-env.sh" >&2
  exit 1
fi

MARCH_DEFAULT="rv64gc_zba_zbb_zbs_zbc_zbkb_zbkx_zkne_zknd_zknh"
MABI_DEFAULT="lp64d"
MARCH="${PQC_MARCH:-$MARCH_DEFAULT}"
MABI="${PQC_MABI:-$MABI_DEFAULT}"

variants=()
if [[ "$VARIANT" = "all" ]]; then
  variants=(baseline optimized)
else
  variants=("$VARIANT")
fi

found_any=0
built_count=0
fail_count=0

compile_one() {
  local variant_name="$1"
  local rel_from_pqc="$2"
  local test_dir="../../tests/pqc/$rel_from_pqc"
  local test_name
  local src_base
  local thash_file
  local elf
  local elf_name

  test_name="$(basename "$rel_from_pqc")"

  if [[ ! -f "$test_dir/main.c" ]]; then
    echo "[skip] missing main.c: $rel_from_pqc"
    return
  fi

  src_base="$test_dir"
  if [[ -f "$test_dir/src/address.c" ]]; then
    src_base="$test_dir/src"
  fi

  thash_file=""
  if [[ -f "$src_base/thash_shake_robust.c" ]]; then
    thash_file="$src_base/thash_shake_robust.c"
  elif [[ -f "$src_base/thash_shake_simple.c" ]]; then
    thash_file="$src_base/thash_shake_simple.c"
  fi

  if [[ -z "$thash_file" ]]; then
    echo "[skip] missing thash source in: $rel_from_pqc"
    return
  fi

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
    ../tests/custom/common/crt.S
  )

  local -a cflags=(
    -O2 -g
    -fno-tree-loop-distribute-patterns
    -static
    -mcmodel=medany
    -fvisibility=hidden
    -nostartfiles
    -lgcc
    -Wl,-gc-sections
    -I../tests/custom/env
    -I../tests/custom/common
    -I"$test_dir"
  )

  # Keep local variant headers first, otherwise generic tests/api.h may shadow them.
  if [[ -d "$test_dir/src" ]]; then
    cflags+=("-I$test_dir/src")
  fi
  if [[ -d "$test_dir/include" ]]; then
    cflags+=("-I$test_dir/include")
  fi
  cflags+=(
    -I../../tests/inc
    -I../../tests
  )

  local -a test_defines=()
  case "$TEST_MODE" in
    keygen)
      test_defines=(-DTEST_KEY=1 -DTEST_SIGN=0 -DTEST_SIGN_OPEN=0)
      ;;
    sign)
      test_defines=(-DTEST_KEY=0 -DTEST_SIGN=1 -DTEST_SIGN_OPEN=0)
      ;;
    sign-open)
      test_defines=(-DTEST_KEY=0 -DTEST_SIGN=0 -DTEST_SIGN_OPEN=1)
      ;;
    auto)
      ;;
  esac

  local out_test_dir="$OUT_ROOT/$variant_name"
  mkdir -p "$out_test_dir"

  if [[ "$TEST_MODE" = "auto" ]]; then
    elf_name="${test_name}.elf"
  else
    elf_name="${test_name}-test-${TEST_MODE}.elf"
  fi
  elf="$out_test_dir/${elf_name}"

  if ! "$RISCV_CC" \
    "$test_dir/main.c" \
    "${src_incs[@]}" \
    "${src_common[@]}" \
    "${cflags[@]}" \
    "${test_defines[@]}" \
    -T../tests/custom/common/test.ld \
    -march="$MARCH" \
    -mabi="$MABI" \
    -o "$elf"; then
    fail_count=$((fail_count + 1))
    echo "[fail] compile failed: $rel_from_pqc" >&2
    return
  fi

  built_count=$((built_count + 1))
  echo "[ok] $rel_from_pqc -> $elf"
}

cd "$REPO_ROOT/verif/sim" || exit 1

for v in "${variants[@]}"; do
  base_dir="$REPO_ROOT/tests/pqc/$v"
  if [[ ! -d "$base_dir" ]]; then
    continue
  fi

  while IFS= read -r run_sh; do
    found_any=1
    rel_dir="${run_sh#"$REPO_ROOT/tests/pqc/"}"
    rel_dir="$(dirname "$rel_dir")"

    if [[ "$FOLDER_NAME" != "all" ]]; then
      if [[ "$(basename "$rel_dir")" != "$FOLDER_NAME" ]]; then
        continue
      fi
    fi

    compile_one "$v" "$rel_dir"
  done < <(find "$base_dir" -type f -name run.sh | sort)
done

if [[ $found_any -eq 0 ]]; then
  echo "No PQC run.sh scripts found under tests/pqc." >&2
  exit 1
fi

if [[ $built_count -eq 0 ]]; then
  echo "No matching folders were built. Check --name/--variant filters." >&2
  exit 1
fi

if [[ $fail_count -gt 0 ]]; then
  echo
  echo "Completed with $fail_count failure(s) and $built_count success(es)." >&2
  exit 1
fi

echo
echo "Generated $built_count elf file(s) under: $OUT_ROOT"
