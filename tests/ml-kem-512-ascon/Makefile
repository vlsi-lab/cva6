# Kyber-Ascon Makefile
# Uses Ascon instead of FIPS-202/Keccak for symmetric primitives
#
# Note: Kyber-Ascon is designed for Kyber-512 (128-bit security level)
# Ascon provides primitives at the 128-bit security level.

CC ?= /usr/bin/cc
CFLAGS += -Wall -Wextra -Wpedantic -Wmissing-prototypes -Wredundant-decls \
  -Wshadow -Wpointer-arith -O3 -fomit-frame-pointer -z noexecstack
NISTFLAGS += -Wno-unused-result -O3 -fomit-frame-pointer
RM = /bin/rm

# Core Kyber sources (same as ref)
SOURCES = kem.c indcpa.c polyvec.c poly.c ntt.c cbd.c reduce.c verify.c

# Ascon sources (replacing FIPS-202/Keccak)
SOURCESASCON = $(SOURCES) ascon.c symmetric-ascon.c

# Headers
HEADERS = params.h kem.h indcpa.h polyvec.h poly.h ntt.h cbd.h reduce.c verify.h symmetric.h
HEADERSASCON = $(HEADERS) ascon.h

.PHONY: all test speed shared clean nistkat

# Default target - build only Kyber-512 (Ascon provides 128-bit security)
all: test

# Test targets - Kyber-512 only for Ascon
test: \
  test/test_kyber512_ascon \
  test/test_vectors512_ascon

# Speed test
speed: \
  test/test_speed512_ascon

# Shared library
shared: \
  lib/libpqcrystals_kyber512_ascon.so \
  lib/libpqcrystals_ascon_ref.so

# NIST KAT - Kyber-512 only
nistkat: \
	nistkat/PQCgenKAT_kem512_ascon

# Shared libraries
lib/libpqcrystals_ascon_ref.so: ascon.c ascon.h
	mkdir -p lib
	$(CC) -shared -fPIC $(CFLAGS) ascon.c -o $@

lib/libpqcrystals_kyber512_ascon.so: $(SOURCES) $(HEADERS) ascon.c symmetric-ascon.c
	mkdir -p lib
	$(CC) -shared -fPIC $(CFLAGS) -DKYBER_K=2 $(SOURCES) ascon.c symmetric-ascon.c -o $@

# Test binaries
test/test_kyber512_ascon: $(SOURCESASCON) $(HEADERSASCON) test/test_kyber.c randombytes.c
	$(CC) $(CFLAGS) -DKYBER_K=2 $(SOURCESASCON) randombytes.c test/test_kyber.c -o $@

test/test_vectors512_ascon: $(SOURCESASCON) $(HEADERSASCON) test/test_vectors.c
	$(CC) $(CFLAGS) -DKYBER_K=2 $(SOURCESASCON) test/test_vectors.c -o $@

test/test_speed512_ascon: $(SOURCESASCON) $(HEADERSASCON) test/cpucycles.h test/cpucycles.c test/speed_print.h test/speed_print.c test/test_speed.c randombytes.c
	$(CC) $(CFLAGS) -DKYBER_K=2 $(SOURCESASCON) randombytes.c test/cpucycles.c test/speed_print.c test/test_speed.c -o $@

# NIST KAT generator
nistkat/PQCgenKAT_kem512_ascon: $(SOURCESASCON) $(HEADERSASCON) nistkat/PQCgenKAT_kem.c nistkat/rng.c nistkat/rng.h
	$(CC) $(NISTFLAGS) -DKYBER_K=2 -o $@ $(SOURCESASCON) nistkat/rng.c nistkat/PQCgenKAT_kem.c $(LDFLAGS) -lcrypto

clean:
	-$(RM) -f *.gcno *.gcda *.lcov *.o *.so
	-$(RM) -f test/test_kyber512_ascon
	-$(RM) -f test/test_vectors512_ascon
	-$(RM) -f test/test_speed512_ascon
	-$(RM) -f nistkat/PQCgenKAT_kem512_ascon
	-$(RM) -f nistkat/*.req
	-$(RM) -f nistkat/*.rsp
	-$(RM) -rf lib/

# Additional targets for convenience
.PHONY: run-test run-kat

run-test: test/test_kyber512_ascon
	./test/test_kyber512_ascon

run-kat: nistkat/PQCgenKAT_kem512_ascon
	cd nistkat && ./PQCgenKAT_kem512_ascon

