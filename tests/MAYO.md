# MAYO on CVA6 bare-metal: what was done, and how to port the next algorithm

This covers `MAYO_1`, `MAYO_2`, `MAYO_3`, `MAYO_5`: how their `run.sh` was built,
what was broken when running MAYO's "opt" C implementation on this bare-metal
CVA6 (`cv64a6_imac_crypto`) target, and a checklist to catch the same problems
early in the next algorithm (CROSS, LESS, HAWK, FAEST, ...) instead of via a
long trial-and-error RTL debugging session.

## 1. run.sh

Each `tests/MAYO_{1,2,3,5}/run.sh` mirrors `tests/ml-kem-512/run.sh`: it compiles
that variant's `main.c` plus `aes_c.c`, `api.c`, `arithmetic.c`, `fips202.c`,
`mayo.c`, `mem.c`, `params.c`, `randombytes_ctrdrbg.c`, links with
`verif/tests/custom/common/{syscalls.c,crt.S}` and `test.ld`, and runs under
`veri-testharness`.

Each variant's parameter set is already hardcoded per-folder in
`mayo_variant.h` (`#define MAYO_VARIANT MAYO_n`), so no `-D` flags are needed
to select it.

One folder-layout gap had to be filled: `main.c` does `#include "inc/uart.h"`,
but unlike `ml-kem-512` (whose `uart.h` sits directly in its own folder), none
of the MAYO folders had an `inc/` subdirectory. Added
`tests/MAYO_{1,2,3,5}/inc/uart.h` (copied from `ml-kem-512/uart.h`) so the
include resolves.

## 2. Runtime fixes (shared infra, not MAYO source)

Two bugs surfaced that had nothing to do with MAYO's algorithm code — they were
missing capabilities in the bare-metal runtime that no earlier test
(`ml-kem-512`, `keccak64`, ...) happened to need. Both fixes live in
`verif/tests/custom/common/`, which every test shares, so they now benefit any
future algorithm automatically. **No changes were made to MAYO's own source**
(`mayo.c`, `fips202.c`, `aes_c.c`, `arithmetic.c`, etc.).

### 2.1 Missing heap (`syscalls.c`)

MAYO's AES key-schedule (`aes_c.c`) and incremental-SHAKE context API
(`fips202.c`) call `malloc`/`free`. This environment never implemented
`_sbrk`, the function newlib's `malloc` needs to grow the heap. Without it,
`malloc` fell back to newlib's default RISC-V `_sbrk`, which issues a raw
`ecall` (Linux `brk` convention) — unhandled here, so it hit the generic
"unhandled trap" path and aborted the test immediately, right after printing
the KAT header and before any real computation started.

Fix — added to `syscalls.c`:

```c
#define HEAP_SIZE (8 * 1024 * 1024)
static char heap[HEAP_SIZE] __attribute__((aligned(16)));
static char *heap_ptr = heap;

void *_sbrk(ptrdiff_t incr)
{
  char *prev = heap_ptr;
  if (heap_ptr + incr > heap + HEAP_SIZE || heap_ptr + incr < heap) {
    return (void *) -1;
  }
  heap_ptr += incr;
  return prev;
}
```

The heap is a static array, so it lives in `.bss`, entirely below the runtime
stack region that `crt.S` carves out starting at `_end` — it can't collide
with the stack. It's a pure bump allocator (never reclaims on `free`), which
is fine for a short KAT run but would leak unbounded memory in a long-running
or looping program.

### 2.2 128KB stack too small (`crt.S`)

MAYO's "opt" implementation keeps large fixed-size scratch buffers on the
stack — e.g. `uint64_t pk[P1_LIMBS_MAX + P2_LIMBS_MAX + P3_LIMBS_MAX]` in
`mayo.c`. Per-variant worst case:

| Variant | Stack buffer size |
|---|---|
| MAYO_1 | ~146 KB |
| MAYO_2 | ~104 KB |
| MAYO_3 | ~384 KB |
| MAYO_5 | ~840 KB |

The old stack allocation (`STKSHIFT=17` in `crt.S`, 128KB per core) was
already too small for MAYO_1 alone. It silently overflowed downward into
adjacent `.bss`/`.data` (including, once fixed, the new heap array), corrupting
state. The corruption didn't crash immediately — it only surfaced later as a
garbage length argument to a `write` syscall, which fesvr's `sys_write` tried
to honor as a `std::vector` size, throwing `std::length_error`. This is why
the crash symptom looked like a testbench/tracer bug rather than a stack
overflow: the failure was far removed from its cause.

Fix — bumped in `crt.S`:

```asm
# give each core 8MB of stack + TLS
#define STKSHIFT 23
```

(was `17` = 128KB; comfortably above MAYO_5's ~840KB single-buffer worst case
plus nested-call overhead; trivial given the SoC has 512MB-1GB of DRAM).

### 2.3 Confirmed result

MAYO_1, full KAT, after both fixes:

```
=== KAT 1/1 ===
-- keygen --
Cycles: 19438174
-- sign --
Cycles: 28900224
-- verify --
Cycles: 18030555
Test Successful (1 KAT vector(s))
*** SUCCESS *** (tohost = 0) after 70138881 cycles
```

Note the cost: ~70 million cycles (~2.4 hours wall clock in RTL simulation)
for one KAT vector of the smallest variant, since this is a generic C
implementation with no RISC-V vector/crypto acceleration. MAYO_5 will be
substantially slower. Budget for this before kicking off a run.

## 3. Checklist for the next algorithm

Run these checks against a new algorithm's vendored source *before* writing
its `run.sh`. Each one maps to a failure mode above (or one that didn't bite
MAYO but plausibly could bite something else, e.g. HAWK's Gaussian sampler).

| # | Check | Command | Why |
|---|---|---|---|
| 1 | Dynamic memory | `grep -rn "malloc(\|calloc(\|realloc(" <dir>` | Now safe (8MB heap, shared fix), but confirms usage exists. Remember it's a leaking bump allocator — fine for one KAT, not for long loops |
| 2 | Large stack buffers | `grep -rn "\[.*_MAX.*\]\|\[.*BYTES.*\]" <dir>/*.c`, eyeball sizes against params | 8MB is generous, but a pathological variant (recursion, very large parameter set) could still exceed it |
| 3 | Floating point | `grep -rn "double\|float" <dir>/*.c` (filter comments) | Target is `rv64imac` — no F/D extension, soft-float ABI (`lp64`). HAWK's Gaussian sampler is the obvious risk: it'll compile via libgcc soft-float emulation but be much slower, and any code assuming hardware FPU rounding modes may misbehave |
| 4 | x86/ARM intrinsics | `grep -rln "immintrin\|arm_neon\|_mm_\|__AVX\|SSE\|AESNI\|NEON" <dir>` | Must be `#ifdef`-guarded with a portable C fallback, like MAYO's `aes_ctr.h`/`arithmetic.h`. Confirm the same pattern before trusting a new algorithm |
| 5 | OS/POSIX assumptions | `grep -rn "fopen\|getenv\|clock_gettime\|pthread\|/dev/urandom\|getrandom" <dir>` | Bare-metal has none of these. Needs a NIST-DRBG-seeded `randombytes` like MAYO's `randombytes_ctrdrbg.c`, not OS entropy |
| 6 | Unaligned pointer casts | `grep -rn "(uint64_t \*)\|(uint32_t \*)" <dir>/*.c` | CVA6 may trap on misaligned load/store with no software emulation configured. Didn't bite MAYO but worth a scan |
| 7 | Folder scaffolding | manual | Needs an `inc/uart.h` (copy from `ml-kem-512`), a `rng.h` shim if the generator's `main.c` hardcodes `#include "rng.h"` but the algorithm's own header is named differently (MAYO needed this — see `rng.h`'s comment), and a variant-select header hardcoding the parameter set (like `mayo_variant.h`) |

If a new algorithm fails at runtime despite passing this checklist, the first
two things to suspect are still stack depth and heap usage under actual
per-variant parameters — the checklist catches the obvious cases, not every
possible size combination.
