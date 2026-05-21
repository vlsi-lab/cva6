# Copyright 2026
# SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
#
# Makefile equivalent of tests/pqc/generate_hex.sh
#
# Generates FPGA-ready .hex files for PQC folders without running
# ISS/simulation. Mirrors the same configuration options as the bash
# script.
#
# Usage:
#   make -C tests/pqc                                  # all variants / all tests
#   make -C tests/pqc VARIANT=optimized
#   make -C tests/pqc NAME=SPHINCS-128f-robust
#   make -C tests/pqc SPHINCS-256f-simple              # positional shorthand
#   make -C tests/pqc TEST=keygen
#   make -C tests/pqc VARIANT=baseline TEST=sign-open
#   make -C tests/pqc clean
#
# Variables (same semantics as generate_hex.sh flags):
#   VARIANT  baseline|optimized|all          (default: all)        -v/--variant
#   NAME     <FOLDER_NAME>|all               (default: all)        -n/--name
#   TEST     auto|keygen|sign|sign-open      (default: auto)       -t/--test
#   OUT      output root directory           (default: tests/pqc/generated_hex)
#   PQC_MARCH/PQC_MABI                       override -march / -mabi
#
# Environment honored (same as the script):
#   PQC_MARCH, PQC_MABI
#

BASE_HEADER := "[PQC HEX]"

# Use bash for recipes (process substitution, pipefail, etc.)
SHELL := /bin/bash

# Paths
MAKEFILE_PATH := $(abspath $(lastword $(MAKEFILE_LIST)))
PQC_DIR       := $(dir $(MAKEFILE_PATH))
REPO_ROOT     := $(abspath $(PQC_DIR)/../..)
SETUP_ENV     := $(REPO_ROOT)/verif/sim/setup-env.sh

# Defaults (overridable on the command line)
VARIANT ?= all
NAME    ?= all
TEST    ?= auto
OUT     ?= $(REPO_ROOT)/tests/pqc/generated_hex

# Toolchain march/mabi defaults (overridable via PQC_MARCH / PQC_MABI like the script)
MARCH_DEFAULT := rv64gc_zba_zbb_zbs_zbc_zbkb_zbkx_zkne_zknd_zknh
MABI_DEFAULT  := lp64d
MARCH         := $(if $(PQC_MARCH),$(PQC_MARCH),$(MARCH_DEFAULT))
MABI          := $(if $(PQC_MABI),$(PQC_MABI),$(MABI_DEFAULT))

# Resolve absolute OUT (allow either absolute or repo-relative)
ifeq ($(patsubst /%,/,$(OUT)),/)
OUT_ABS := $(OUT)
else
OUT_ABS := $(REPO_ROOT)/$(OUT)
endif

# Positional shorthand: any goal that is not a known target is treated as NAME.
KNOWN_GOALS := all clean help
GOALS       := $(MAKECMDGOALS)
POSITIONAL  := $(filter-out $(KNOWN_GOALS),$(GOALS))
ifneq ($(strip $(POSITIONAL)),)
  ifneq ($(words $(POSITIONAL)),1)
    $(error Only one positional FOLDER_NAME is allowed, got: $(POSITIONAL))
  endif
  NAME := $(POSITIONAL)
endif

# Validate VARIANT
ifeq ($(filter $(VARIANT),all baseline optimized),)
  $(error Invalid VARIANT='$(VARIANT)' (allowed: baseline|optimized|all))
endif

# Validate TEST
ifeq ($(filter $(TEST),auto keygen sign sign-open),)
  $(error Invalid TEST='$(TEST)' (allowed: auto|keygen|sign|sign-open))
endif

# Variant list
ifeq ($(VARIANT),all)
  VARIANT_LIST := baseline optimized
else
  VARIANT_LIST := $(VARIANT)
endif

# TEST -> defines
ifeq ($(TEST),keygen)
  TEST_DEFINES := -DTEST_KEY=1 -DTEST_SIGN=0 -DTEST_SIGN_OPEN=0
  HEX_SUFFIX   := -test-keygen
else ifeq ($(TEST),sign)
  TEST_DEFINES := -DTEST_KEY=0 -DTEST_SIGN=1 -DTEST_SIGN_OPEN=0
  HEX_SUFFIX   := -test-sign
else ifeq ($(TEST),sign-open)
  TEST_DEFINES := -DTEST_KEY=0 -DTEST_SIGN=0 -DTEST_SIGN_OPEN=1
  HEX_SUFFIX   := -test-sign-open
else
  TEST_DEFINES :=
  HEX_SUFFIX   :=
endif

# Shell helper that sources the cva6 setup env and exports RISCV_CC/RISCV_OBJCOPY.
# Used inside recipe shells via `eval "$(SETUP_TOOLCHAIN)"`.
define SETUP_TOOLCHAIN_SH
set -uo pipefail; \
if [ ! -f "$(SETUP_ENV)" ]; then \
  echo "Error: missing $(SETUP_ENV)" >&2; exit 1; \
fi; \
: $${LD_LIBRARY_PATH:=}; \
set +u; . "$(SETUP_ENV)"; set -u; \
if [ -z "$${RISCV_CC:-}" ] || [ -z "$${RISCV_OBJCOPY:-}" ]; then \
  echo "Error: RISCV_CC/RISCV_OBJCOPY are not set after setup-env.sh" >&2; exit 1; \
fi
endef

.PHONY: all clean help $(POSITIONAL)
.DEFAULT_GOAL := all

# Positional goals are no-ops (they only configure NAME).
$(POSITIONAL):
	@:

help:
	@echo "Usage: make -C tests/pqc [VARIANT=...] [NAME=...] [TEST=...] [OUT=...] [target]"
	@echo ""
	@echo "Variables:"
	@echo "  VARIANT  baseline|optimized|all          (default: all)"
	@echo "  NAME     <FOLDER_NAME>|all               (default: all)"
	@echo "  TEST     auto|keygen|sign|sign-open      (default: auto)"
	@echo "  OUT      output root directory           (default: tests/pqc/generated_hex)"
	@echo ""
	@echo "Targets:"
	@echo "  all      Build hex files (default)"
	@echo "  clean    Remove all .hex files under OUT"
	@echo "  help     Show this help"
	@echo ""
	@echo "Examples:"
	@echo "  make -C tests/pqc"
	@echo "  make -C tests/pqc VARIANT=optimized"
	@echo "  make -C tests/pqc NAME=SPHINCS-128f-robust"
	@echo "  make -C tests/pqc SPHINCS-256f-simple"
	@echo "  make -C tests/pqc TEST=keygen"
	@echo "  make -C tests/pqc clean"

all:
	@mkdir -p "$(OUT_ABS)"
	@echo $(BASE_HEADER) Output root: $(OUT_ABS)
	@echo $(BASE_HEADER) Variants  : $(VARIANT_LIST)
	@echo $(BASE_HEADER) Name      : $(NAME)
	@echo $(BASE_HEADER) Test mode : $(TEST)
	@echo $(BASE_HEADER) march/mabi: $(MARCH) / $(MABI)
	@set -uo pipefail; \
	$(SETUP_TOOLCHAIN_SH); \
	BUILD_DIR="$$(mktemp -d "$(REPO_ROOT)/verif/sim/.pqc_hex_build.XXXXXX")"; \
	trap 'rm -rf "$$BUILD_DIR"' EXIT; \
	cd "$(REPO_ROOT)/verif/sim"; \
	found_any=0; built_count=0; fail_count=0; \
	for v in $(VARIANT_LIST); do \
	  base_dir="$(REPO_ROOT)/tests/pqc/$$v"; \
	  if [ ! -d "$$base_dir" ]; then continue; fi; \
	  while IFS= read -r run_sh; do \
	    found_any=1; \
	    rel_dir="$${run_sh#$(REPO_ROOT)/tests/pqc/}"; \
	    rel_dir="$$(dirname "$$rel_dir")"; \
	    test_name="$$(basename "$$rel_dir")"; \
	    if [ "$(NAME)" != "all" ] && [ "$$test_name" != "$(NAME)" ]; then continue; fi; \
	    test_dir="../../tests/pqc/$$rel_dir"; \
	    if [ ! -f "$$test_dir/main.c" ]; then \
	      echo "[skip] missing main.c: $$rel_dir"; continue; \
	    fi; \
	    src_base="$$test_dir"; \
	    if [ -f "$$test_dir/src/address.c" ]; then src_base="$$test_dir/src"; fi; \
	    thash_file=""; \
	    if [ -f "$$src_base/thash_shake_robust.c" ]; then \
	      thash_file="$$src_base/thash_shake_robust.c"; \
	    elif [ -f "$$src_base/thash_shake_simple.c" ]; then \
	      thash_file="$$src_base/thash_shake_simple.c"; \
	    fi; \
	    if [ -z "$$thash_file" ]; then \
	      echo "[skip] missing thash source in: $$rel_dir"; continue; \
	    fi; \
	    src_incs="$$src_base/address.c $$src_base/fips202.c $$src_base/fors.c \
	              $$src_base/hash_shake.c $$src_base/merkle.c $$src_base/randombytes.c \
	              $$src_base/sign.c $$thash_file $$src_base/utils.c $$src_base/utilsx1.c \
	              $$src_base/wots.c $$src_base/wotsx1.c"; \
	    if [ "$$v" = "optimized" ] && [ -f "$$src_base/keccak_coproc.S" ]; then \
	      src_incs="$$src_incs $$src_base/keccak_coproc.S"; \
	    fi; \
	    src_common="../tests/custom/common/syscalls.c ../tests/custom/common/crt.S"; \
	    cflags="-O2 -g -fno-tree-loop-distribute-patterns -static -mcmodel=medany \
	            -fvisibility=hidden -nostartfiles -lgcc -Wl,-gc-sections \
	            -I../tests/custom/env -I../tests/custom/common -I$$test_dir"; \
	    if [ -d "$$test_dir/src" ];     then cflags="$$cflags -I$$test_dir/src"; fi; \
	    if [ -d "$$test_dir/include" ]; then cflags="$$cflags -I$$test_dir/include"; fi; \
	    cflags="$$cflags -I../../tests/inc -I../../tests"; \
	    out_test_dir="$(OUT_ABS)/$$v"; \
	    mkdir -p "$$out_test_dir"; \
	    elf="$$BUILD_DIR/$${v}_$${test_name}.elf"; \
	    hex="$$out_test_dir/$${test_name}$(HEX_SUFFIX).hex"; \
	    if ! "$$RISCV_CC" \
	        "$$test_dir/main.c" $$src_incs $$src_common $$cflags \
	        $(TEST_DEFINES) \
	        -T../tests/custom/common/test.ld \
	        -march=$(MARCH) -mabi=$(MABI) \
	        -o "$$elf"; then \
	      fail_count=$$((fail_count + 1)); \
	      echo "[fail] compile failed: $$rel_dir" >&2; \
	      continue; \
	    fi; \
	    if ! "$$RISCV_OBJCOPY" -O verilog "$$elf" "$$hex"; then \
	      fail_count=$$((fail_count + 1)); \
	      echo "[fail] objcopy failed: $$rel_dir" >&2; \
	      continue; \
	    fi; \
	    built_count=$$((built_count + 1)); \
	    echo "[ok] $$rel_dir -> $$hex"; \
	  done < <(find "$$base_dir" -type f -name run.sh | sort); \
	done; \
	if [ $$found_any -eq 0 ]; then \
	  echo "No PQC run.sh scripts found under tests/pqc." >&2; exit 1; \
	fi; \
	if [ $$built_count -eq 0 ]; then \
	  echo "No matching folders were built. Check NAME/VARIANT filters." >&2; exit 1; \
	fi; \
	if [ $$fail_count -gt 0 ]; then \
	  echo; \
	  echo "Completed with $$fail_count failure(s) and $$built_count success(es)." >&2; \
	  exit 1; \
	fi; \
	echo; \
	echo "Generated $$built_count hex file(s) under: $(OUT_ABS)"

clean:
	@if [ ! -d "$(OUT_ABS)" ]; then \
	  echo "No output directory to clean: $(OUT_ABS)"; \
	  exit 0; \
	fi; \
	hex_count="$$(find "$(OUT_ABS)" -type f -name '*.hex' | wc -l)"; \
	if [ "$$hex_count" -eq 0 ]; then \
	  echo "No .hex files found under: $(OUT_ABS)"; \
	  exit 0; \
	fi; \
	find "$(OUT_ABS)" -type f -name '*.hex' -delete; \
	echo "Removed $$hex_count .hex file(s) under: $(OUT_ABS)"
