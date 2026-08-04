// Shared clock-cycle + retired-instruction counting helpers, built on the
// mcycle/minstret CSRs (encoding.h's read_csr/write_csr/clear_csr macros,
// same pattern already used by tests/keccak64/*.c for mcycle alone).

#ifndef __BENCH_H__
#define __BENCH_H__

#include "encoding.h"

// mcountinhibit bit 0 = CY (mcycle), bit 2 = IR (minstret). Clearing both
// enables counting of both at once.
#define BENCH_ENABLE() clear_csr(mcountinhibit, 0x5)

#define BENCH_START() \
  do { \
    write_csr(mcycle, 0); \
    write_csr(minstret, 0); \
  } while (0)

#define BENCH_READ(cycles, instrs) \
  do { \
    (cycles) = read_csr(mcycle); \
    (instrs) = read_csr(minstret); \
  } while (0)

#endif
