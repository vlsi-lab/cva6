// SPDX-License-Identifier: Apache-2.0
//
// Compatibility shim: tools/gen_static_test.py's "ds_drbg_hawk" shape
// renderer (shared with HAWK/FAEST/UOV) hardcodes `#include "rng.h"` in the
// static-test main.c it generates. MAYO-C's own DRBG header is named
// randombytes.h (see include/randombytes.h) -- this just aliases it so the
// generated main.c resolves, without renaming anything upstream.
#ifndef MAYO_RNG_SHIM_H
#define MAYO_RNG_SHIM_H
#include "randombytes.h"
#endif
