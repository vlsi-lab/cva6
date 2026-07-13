# Host-native sanity check for ML-DSA-2 (Ascon-substituted), before going
# anywhere near the RISC-V/RTL simulation flow. Builds and runs with the
# system gcc -- NOT the RISC-V cross toolchain, NOT cva6/Verilator.
#
# Performance-counter instrumentation (mcycle/minstret via encoding.h) is a
# RISC-V-only CSR feature, so it's forced off here (-DPERF_CNT_CYCLES=0);
# main.c #ifndef-guards that define, so this override actually takes effect.
#
# DILITHIUM_MODE selects the security level this directory was generated
# for; config.h defaults to mode 2 regardless of directory name, so it must
# be passed explicitly here too.

CC             ?= gcc
CFLAGS         ?= -O2 -Wall
DILITHIUM_MODE := 2
DEFS           := -DPERF_CNT_CYCLES=0 -DDILITHIUM_MODE=$(DILITHIUM_MODE)

SOURCES := main.c ascon.c ntt.c packing.c poly.c polyvec.c reduce.c \
           rounding.c sign.c symmetric-ascon.c

BIN := ML-DSA-2_host_test

.PHONY: all run clean

all: $(BIN)

$(BIN): $(SOURCES)
	$(CC) $(CFLAGS) $(DEFS) -I. -o $@ $(SOURCES)

run: $(BIN)
	./$(BIN)

clean:
	rm -f $(BIN)
