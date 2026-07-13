# Host-native sanity check for ml-kem-1024 (Keccak-loosely-accelerated),
# before going anywhere near the RISC-V/RTL simulation flow. Builds and
# runs with the system gcc -- NOT the RISC-V cross toolchain, NOT
# cva6/Verilator.
#
# Performance-counter instrumentation (mcycle/minstret via encoding.h) is a
# RISC-V-only CSR feature, so it's forced off here (-DPERF_CNT_CYCLES=0);
# main.c #ifndef-guards that define, so this override actually takes effect.
#
# USE_COPROCESSOR_AXI is never defined here: the AXI coprocessor is a
# memory-mapped device that only exists in the cva6 RTL simulation, so the
# host build always uses the plain-software Keccak-f[1600] permutation.

CC      ?= gcc
CFLAGS  ?= -O2 -Wall
DEFS    := -DPERF_CNT_CYCLES=0

SOURCES := main.c cbd.c fips202.c indcpa.c kem.c ntt.c poly.c polyvec.c \
           randombytes.c reduce.c symmetric-shake.c verify.c

BIN := ml-kem-1024_host_test

.PHONY: all run clean

all: $(BIN)

$(BIN): $(SOURCES)
	$(CC) $(CFLAGS) $(DEFS) -I. -o $@ $(SOURCES)

run: $(BIN)
	./$(BIN)

clean:
	rm -f $(BIN)
