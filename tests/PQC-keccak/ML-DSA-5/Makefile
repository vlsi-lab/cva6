# Host-native sanity check for ML-DSA-5 (Keccak-loosely-accelerated), before
# going anywhere near the RISC-V/RTL simulation flow. Builds and runs with
# the system gcc -- NOT the RISC-V cross toolchain, NOT cva6/Verilator.
#
# Performance-counter instrumentation (mcycle/minstret via encoding.h) is a
# RISC-V-only CSR feature, so it's forced off here (-DPERF_CNT_CYCLES=0);
# main.c #ifndef-guards that define, so this override actually takes effect.
#
# DILITHIUM_MODE selects the security level this directory was generated
# for; config.h defaults to mode 2 regardless of directory name, so it must
# be passed explicitly here too.
#
# USE_COPROCESSOR_AXI is never defined here: the AXI coprocessor is a
# memory-mapped device that only exists in the cva6 RTL simulation, so the
# host build always uses the plain-software Keccak-f[1600] permutation.

CC             ?= gcc
CFLAGS         ?= -O2 -Wall
DILITHIUM_MODE := 5
DEFS           := -DPERF_CNT_CYCLES=0 -DDILITHIUM_MODE=$(DILITHIUM_MODE)

SOURCES := main.c fips202.c ntt.c packing.c poly.c polyvec.c reduce.c \
           rounding.c sign.c symmetric-shake.c

BIN := ML-DSA-5_host_test

.PHONY: all run clean

all: $(BIN)

$(BIN): $(SOURCES)
	$(CC) $(CFLAGS) $(DEFS) -I. -o $@ $(SOURCES)

run: $(BIN)
	./$(BIN)

clean:
	rm -f $(BIN)
