# FAEST on CVA6 bare-metal: what was done, and how to port the next algorithm

This covers all 12 FAEST variants: `FAEST_128F`, `FAEST_128S`, `FAEST_192F`,
`FAEST_192S`, `FAEST_256F`, `FAEST_256S`, `FAEST_EM_128F`, `FAEST_EM_128S`,
`FAEST_EM_192F`, `FAEST_EM_192S`, `FAEST_EM_256F`, `FAEST_EM_256S`.

Same exercise as [MAYO.md](MAYO.md): get `run.sh` working for each variant on
bare-metal CVA6 (`cv64a6_imac_crypto`), record what broke and why, and update
the porting checklist so the next algorithm (CROSS, LESS, HAWK, ...) costs
less to bring up.

## 1. run.sh

Each `tests/FAEST_*/run.sh` mirrors the MAYO/`ml-kem-512` pattern: compile that
variant's `main.c` plus the 20 files shared across all 12 folders (`aes.c`,
`bavc.c`, `compat.c`, `cpu.c`, `crypto_sign.c`, `faest_aes_{128,192,256}.c`,
`faest_impl.c`, `fields.c`, `instances.c`, `owf.c`, `random_oracle.c`,
`randomness.c`, `rng.c`, `universal_hashing.c`, `utils.c`, `vole.c`,
`KeccakHash.c`, `KeccakP-1600-opt64.c`, `KeccakSponge.c`) plus that one
variant's top-level file (`faest_128f.c`, ..., `faest_em_256s.c`), link with
`verif/tests/custom/common/{syscalls.c,crt.S}` and `test.ld`.

Each folder's `crypto_sign.c` already `#include`s its own variant's header
(e.g. `faest_128f.h`) and calls that variant's `faest_128f_keygen`/`_sign`/
`_verify` directly — no `-D` flag needed to select the parameter set, same as
MAYO's `mayo_variant.h` pattern.

Same folder-layout gap as MAYO: `main.c` does `#include "inc/uart.h"`, so
`inc/uart.h` (copied from `ml-kem-512/uart.h`) was added to all 12 folders.

## 2. Checking the porting checklist first

Before writing anything, ran the [MAYO.md](MAYO.md) checklist against
`FAEST_128F`'s source (all 12 variants share the same non-variant-specific
files, so one pass covers all of them). Two things stood out:

### 2.1 Heavier heap usage than MAYO (checklist item 1)

FAEST's BAVC (vector commitment tree) and VOLE code allocate proportionally
to the parameter set (`L`, `tau`), e.g. `calloc(2*L-1, lambda_bytes)`,
`malloc(L*com_size)`. Computed FAEST_256F's worst case at roughly 1-2MB
across a full keygen+sign+verify run. Since `_sbrk` (added for MAYO) is a
non-reclaiming bump allocator — every `malloc` across a whole run accumulates,
`free()` never gives space back — bumped the shared heap in
`verif/tests/custom/common/syscalls.c` from 8MB to 64MB *before* running
anything, trading a few bytes of unused `.bss` for headroom that's free given
the SoC's 512MB-1GB DRAM.

### 2.2 Everything else came back clean

- AES-NI/AVX2/NEON (`cpu.c`, `aesni.h`): properly `#ifdef HAVE_AESNI`/CPU-arch
  guarded, falls through to "no features detected" on RISC-V. Real x86 CPUID
  detection exists in `cpu.c` but is dead code here (`#elif` chain ends in
  `return 0` for unrecognized architectures).
- `getrandom()`/`/dev/urandom` (`randomness.c`): dead code. A `#if 1` at the
  top of the file (`/* pqrv: always use the injected NIST-framework
  randombytes() */`) always redirects to the same deterministic,
  KAT-seed-driven DRBG that `rng.c` implements, regardless of platform.
- OpenSSL (`rng.c`): already `#if 0`'d out in favor of a portable AES-256/ECB
  fallback (comment: "modified to include a perfunctory AES-256/ECB
  implementation ... instead of using OpenSSL").
- No floating point anywhere in the signing/verification path.
- `<malloc.h>`/`<features.h>`/`<endian.h>`/`<Availability.h>` angle-bracket
  system includes: all correctly platform-guarded (or, for `<malloc.h>`,
  simply exist in this newlib toolchain) and never resolve to a problematic
  path for this target.

## 3. The crash: misaligned load in Keccak (checklist item 6, confirmed)

FAEST_128F ran cleanly through keygen, then crashed partway through sign:

```
=== KAT 1/1 ===
-- keygen --
Cycles: 274936
-- sign --
*** FAILED *** (tohost = 1337) after 1120758 cycles
```

### 3.1 Diagnosing it

The shared trap handler (`handle_trap` in `syscalls.c`) only ever reported the
generic sentinel `tohost = 1337` for *any* unhandled hardware trap, with no
detail — that was enough for MAYO's stack-overflow/`_sbrk` bugs (which were
found by other means) but not enough here. Added permanent diagnostics to
`syscalls.c` so any future crash in any algorithm prints the actual fault
before exiting:

```c
static const char *mcause_name(uintptr_t cause) { ... }   // decodes RISC-V mcause to a string

uintptr_t __attribute__((weak)) handle_trap(uintptr_t cause, uintptr_t epc, uintptr_t regs[32])
{
  printf("FATAL: unhandled trap: mcause=0x%lx (%s) mepc=0x%lx ra=0x%lx sp=0x%lx\n",
         (unsigned long) cause, mcause_name(cause), (unsigned long) epc,
         (unsigned long) regs[1], (unsigned long) regs[2]);
  tohost_exit(1337);
}
```

Rebuilding and re-running FAEST_128F with this in place immediately gave:

```
FATAL: unhandled trap: mcause=0x4 (load address misaligned) mepc=0x80002404 ra=0x80002568 sp=0x84849ec0
```

`riscv-none-elf-addr2line -f -C 0x80002404 0x80002568` on the built ELF
resolved this to:

```
KeccakP1600_AddLanes
tests/FAEST_128F/KeccakP-1600-opt64.c:157
KeccakP1600_AddBytes
tests/FAEST_128F/KeccakP-1600-opt64.c:196
```

### 3.2 Root cause

FAEST vendors XKCP's Keccak-p[1600] permutation, "opt64" variant
(`KeccakP-1600-opt64.c`). Several of its functions cast caller-supplied
`unsigned char *` byte buffers directly to `uint64_t *` and do wide loads and
stores — safe and fast on x86-64/ARM64 (both tolerate misaligned access in
hardware), but CVA6 does not: it traps on any load/store whose address isn't
naturally aligned to its width, and nothing in this bare-metal environment
catches or emulates that trap. This is exactly checklist item 6
("unaligned pointer casts") from `MAYO.md` — flagged there as a risk that
hadn't bitten MAYO but "worth a scan" for future algorithms. It bit FAEST.

Only one of the affected functions (`KeccakP1600_AddLanes`) had *any*
alignment awareness at all, and it was dead: gated behind a
`#ifdef NO_MISALIGNED_ACCESSES` that nothing defined. Three more functions
had no guard whatsoever:

| Function | Problem |
|---|---|
| `KeccakP1600_AddLanes` | Alignment check existed but was compiled out (macro never defined) |
| `KeccakP1600_ExtractAndAddLanes` | Unconditional `((uint64_t*)output)[i] = ((uint64_t*)input)[i] ^ state[i]` |
| `KeccakF1600_FastLoop_Absorb` | Unconditional `uint64_t *inDataAsLanes = (uint64_t*)data` fed straight into the round-absorption macro |
| `KeccakP1600_12rounds_FastLoop_Absorb` | Same as above, 12-round variant |

Two considered fixes:
1. **Patch the vendored XKCP file** (narrow, chosen) — fast, low-risk, fixes
   FAEST specifically.
2. **Emulate misaligned load/store in the trap handler** (systemic) — would
   fix this class of bug permanently for every current and future algorithm,
   anywhere in their code, not just this one file. More code, needs careful
   instruction-decode testing (including compressed `c.ld`/`c.sd` forms).

Went with option 1 for now given the scope of this task; option 2 remains
worth doing later if another algorithm hits the same class of bug in a
different file (see checklist update below).

### 3.3 The patch

All four functions patched in `KeccakP-1600-opt64.c` to never assume
alignment, using `memcpy` (which is alignment-safe regardless of platform)
instead of raw pointer casts on caller-supplied buffers. `state` itself
(the internal 25-lane permutation array) is always properly aligned and was
left as a direct `uint64_t*` cast in all cases — only external byte buffers
(`data`, `input`, `output`) needed fixing.

- `KeccakP1600_AddLanes`: removed the `#ifdef NO_MISALIGNED_ACCESSES` guard
  around the existing alignment check so it's always active, not
  conditional on an unused build flag.
- `KeccakP1600_ExtractAndAddLanes`: replaced the direct cast/XOR with
  `memcpy` into/out of local `uint64_t` temporaries.
- `KeccakF1600_FastLoop_Absorb` / `KeccakP1600_12rounds_FastLoop_Absorb`:
  replaced `inDataAsLanes = (uint64_t*)data` with a small (21-lane, the
  maximum possible rate) aligned local buffer, `memcpy`'d from `data` once
  per loop iteration before feeding it to the `addInput()` macro.

This file is byte-identical across all 12 FAEST folders (verified via
`md5sum` before patching), so the fix was applied once and copied to all 12.

### 3.4 Status

Re-running FAEST_128F with the patch to confirm the fix resolves the crash
(and doesn't just move it further into sign/verify) — in progress as of this
writing. Update this section once confirmed.

## 4. Checklist updates for the next algorithm

Everything from [MAYO.md](MAYO.md)'s checklist still applies. Refinements
from this pass:

- **Item 1 (dynamic memory)**: also estimate total *volume*, not just
  presence. A non-reclaiming bump allocator means total heap use is the sum
  across an entire run, not the peak at any one instant. If an algorithm's
  allocations scale with a tree/graph parameter (like FAEST's `L`), compute
  the worst-case variant's total before running, and size the shared heap
  with headroom — cheap given available DRAM, and avoids yet another
  crash-and-debug cycle.
- **Item 6 (unaligned pointer casts)**: confirmed as a real, recurring risk
  class, not hypothetical. Any vendored code casting an external byte buffer
  to a wider integer type is suspect — grep for `(uint64_t *)`/`(uint32_t *)`
  applied to function *parameters* specifically (as opposed to internal,
  always-aligned state/context structs), and check whether the existing code
  already has an alignment-safety fallback (as XKCP does for one function)
  before assuming the rest of the file follows the same pattern — it may not.
  Since XKCP is a widely-reused Keccak/SHA-3 implementation, any other
  algorithm vendoring it (CROSS, LESS, HAWK, if they use the same "opt64"
  variant) should have its `KeccakP-1600-opt64.c` checked/patched the same
  way *before* running, not after a crash.
- **New: crash diagnostics are now permanent.** `handle_trap` in
  `verif/tests/custom/common/syscalls.c` now prints the decoded `mcause`,
  `mepc`, `ra`, and `sp` for any unhandled trap in any test, instead of only
  the generic `tohost = 1337` sentinel. Combined with
  `riscv-none-elf-addr2line -f -C <mepc> <ra>` against the built `main.o`,
  this turns "why did it crash" into a direct source-line answer instead of
  a guessing exercise — use it first on any future crash.
