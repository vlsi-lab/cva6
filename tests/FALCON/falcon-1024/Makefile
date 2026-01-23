# ****************************************************************************
#
# Auth: Alessandra Dolmeta - Politecnico di Torino
# Date: August 2024
# ****************************************************************************

# Compiled application has the same name of its folder
APPLI   = $(shell basename $(CURDIR))
SOURCES = src/codec.c src/common.c src/fft.c src/fpr.c src/keygen.c src/nist.c src/rng.c src/shake.c src/sign.c src/vrfy.c
SRC     = $(SOURCES) \
          main.c

INC         = -I include/ -I
EXTRA_CFLAGS = -g -O2

# Conditional flags based on the defined parameters
ifdef NTESTS
EXTRA_CFLAGS += -DNTESTS=$(NTESTS)
endif

# Part to test
TEST_KEY ?= 1
TEST_SIGN ?= 1
TEST_SIGN_OPEN ?= 1

# Debug
PRINT_VECT   ?= 0

# Performance counters
PERF_CNT_CYCLES ?= 0
PERF_CNT_INSTR  ?= 0

# Add the test parameters to EXTRA_CFLAGS
EXTRA_CFLAGS += -DTEST_KEY=$(TEST_KEY) -DTEST_ENC=$(TEST_ENC) -DTEST_DEC=$(TEST_DEC)
EXTRA_CFLAGS += -DPRINT_VECT=$(PRINT_VECT)
EXTRA_CFLAGS += -DTEST_VECT_INCLUDE="\"test_vectors_1024.h\""

# Debug print statements
$(info APPLI: $(APPLI))
$(info EXTRA_CFLAGS: $(EXTRA_CFLAGS))
$(info PRINT_VECT: $(PRINT_VECT))
# Compiler
CC = gcc

# Targets
all: $(APPLI)

$(APPLI): $(SRC)
	$(CC) $(SRC) $(INC) $(EXTRA_CFLAGS) -o $(APPLI)

clean:
	rm -f $(APPLI)

.PHONY: all clean
