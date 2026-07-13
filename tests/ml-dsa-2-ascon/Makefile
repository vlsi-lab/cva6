# Dilithium-Ascon Makefile
# Uses Ascon instead of FIPS-202/Keccak for symmetric primitives
#
# Note: Dilithium-Ascon is designed for Dilithium-2 (128-bit security level)
# Ascon provides primitives at the 128-bit security level.

CC ?= /usr/bin/cc
CFLAGS += -Wall -Wextra -Wpedantic -Wmissing-prototypes -Wredundant-decls \
  -Wshadow -Wvla -Wpointer-arith -O3 -fomit-frame-pointer
NISTFLAGS += -Wno-unused-result -O3 -fomit-frame-pointer
RM = /bin/rm

# Core Dilithium sources (same as ref)
SOURCES = sign.c packing.c polyvec.c poly.c ntt.c reduce.c rounding.c

# Ascon sources (replacing FIPS-202/Keccak)
SOURCESASCON = $(SOURCES) ascon.c symmetric-ascon.c

# Headers
HEADERS = config.h params.h api.h sign.h packing.h polyvec.h poly.h ntt.h \
  reduce.h rounding.h symmetric.h randombytes.h
HEADERSASCON = $(HEADERS) ascon.h

.PHONY: all test speed shared clean nistkat

# Default target - build only Dilithium-2 (Ascon provides 128-bit security)
all: test

# Test targets - Dilithium-2 only for Ascon
test: \
  test/test_dilithium2_ascon \
  test/test_vectors2_ascon

# Speed test
speed: \
  test/test_speed2_ascon \
  test/test_mul_ascon

# Shared library
shared: \
  libpqcrystals_dilithium2_ascon.so \
  libpqcrystals_ascon_ref.so

# NIST KAT - Dilithium-2 only
nistkat: \
	nistkat/PQCgenKAT_sign2_ascon

# Shared libraries
libpqcrystals_ascon_ref.so: ascon.c ascon.h
	$(CC) -shared -fPIC $(CFLAGS) -o $@ ascon.c

libpqcrystals_dilithium2_ascon.so: $(SOURCES) $(HEADERS) ascon.c symmetric-ascon.c
	$(CC) -shared -fPIC $(CFLAGS) -DDILITHIUM_MODE=2 \
	  -o $@ $(SOURCES) ascon.c symmetric-ascon.c

# Test binaries
test/test_dilithium2_ascon: test/test_dilithium.c randombytes.c $(SOURCESASCON) $(HEADERSASCON)
	$(CC) $(CFLAGS) -DDILITHIUM_MODE=2 \
	  -o $@ test/test_dilithium.c randombytes.c $(SOURCESASCON)

test/test_vectors2_ascon: test/test_vectors.c $(SOURCESASCON) $(HEADERSASCON)
	$(CC) $(CFLAGS) -DDILITHIUM_MODE=2 \
	  -o $@ test/test_vectors.c $(SOURCESASCON)

test/test_speed2_ascon: test/test_speed.c test/speed_print.c test/speed_print.h \
  test/cpucycles.c test/cpucycles.h randombytes.c $(SOURCESASCON) $(HEADERSASCON)
	$(CC) $(CFLAGS) -DDILITHIUM_MODE=2 \
	  -o $@ test/test_speed.c test/speed_print.c test/cpucycles.c randombytes.c \
	  $(SOURCESASCON)

test/test_mul_ascon: test/test_mul.c randombytes.c $(SOURCESASCON) $(HEADERSASCON)
	$(CC) $(CFLAGS) -UDBENCH -o $@ test/test_mul.c randombytes.c $(SOURCESASCON)

# NIST KAT generator
nistkat/PQCgenKAT_sign2_ascon: nistkat/PQCgenKAT_sign.c nistkat/rng.c nistkat/rng.h \
  $(SOURCESASCON) $(HEADERSASCON)
	$(CC) $(NISTFLAGS) -DDILITHIUM_MODE=2 \
	  -o $@ nistkat/PQCgenKAT_sign.c nistkat/rng.c $(SOURCESASCON) $(LDFLAGS) -lcrypto

clean:
	-$(RM) -f *~ test/*~ *.gcno *.gcda *.lcov *.o *.so
	-$(RM) -f libpqcrystals_dilithium2_ascon.so
	-$(RM) -f libpqcrystals_ascon_ref.so
	-$(RM) -f test/test_dilithium2_ascon
	-$(RM) -f test/test_vectors2_ascon
	-$(RM) -f test/test_speed2_ascon
	-$(RM) -f test/test_mul_ascon
	-$(RM) -f nistkat/PQCgenKAT_sign2_ascon
	-$(RM) -f nistkat/*.req
	-$(RM) -f nistkat/*.rsp

# Additional targets for convenience
.PHONY: run-test run-kat

run-test: test/test_dilithium2_ascon
	./test/test_dilithium2_ascon

run-kat: nistkat/PQCgenKAT_sign2_ascon
	cd nistkat && ./PQCgenKAT_sign2_ascon

