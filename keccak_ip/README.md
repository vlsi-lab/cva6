# keccak_ip register interface: design history

This IP is a loosely-coupled (AXI/MMIO) Keccak-f[1600] permutation accelerator:
`reggen`-generated register file (`gen/keccak_reg_top.sv`, from `keccak.hjson`) sits on
the bus side, `rtl/keccak_f.sv` (`keccak_cu` + `keccak_dp`) does the 24-round
permutation, `rtl/keccak_axi_top.sv` glues the two together.

The register interface went through three real designs, each measured on RTL
(`tests/keccak64/keccak_axi.c`, `veri-testharness`, target `cv64a6_imac_crypto`,
known-answer-test vector). This doc records what each one looked like, why it changed,
and the actual trade-off — so the next similar loosely-coupled IP doesn't have to
rediscover the same lessons.

| # | Design | Cycles (KAT permute) | State duplicated? |
|---|--------|----------------------|--------------------|
| 1 | Bulk 25-register + private copy | 495 | Yes |
| 2 | Streaming `CTRL.IDX`+`DATA_IN`+`DATA_OUT`, explicit `WR_VALID` | 2212 | No |
| 3 | Streaming, `hwqe` write-pulse instead of `WR_VALID` | 1851 | No |
| 4 | Bulk 25-register, register file **is** the compute state | **558** | No |

## 1. Original: bulk 25-register file + private copy inside the core

`keccak.hjson` exposed the whole 1600-bit state as 25 independent 64-bit `DATA[i]`
registers (`swaccess: rw`, plain `hwaccess: hro` — software-writable, hardware
read-only). `keccak_dp` then had its own internal `reg_data` (`k_state`, a
`logic[4:0][4:0][64]` packed array): on `start_i`, the whole 1600-bit bus-facing array
was bulk-copied into `reg_data` before running 24 rounds, and copied back out
afterward.

**Why it was fast (495 cycles):** the 25 `DATA[i]` registers are mutually
independent addresses, so software can write/read all of them back-to-back with no
ordering dependency between any two of them — fully pipelinable across the AXI
interconnect, no `fence` needed anywhere except around the real `START`/`DONE`
handshake.

**The problem:** the same 1600 bits physically existed in two places — the bus-facing
register file and `keccak_dp`'s private array — for the entire duration of every
permutation. For a bigger core (or one instantiated many times) that's wasted flip-flops
purely as an artifact of the register interface shape, not anything intrinsic to the
algorithm.

## 2 & 3. Streaming interface: collapse to one copy, indexed word-at-a-time

First attempt at removing the duplication: shrink the register file down to
`CTRL` (`START`/`DONE`/`IDX`) + `DATA_IN` + `DATA_OUT`, and let `keccak_dp`'s
`reg_data` be the *only* 1600-bit storage. Software streams the state in/out one
64-bit word at a time: set `IDX`, then write `DATA_IN` (committed into
`reg_data[IDX]`) or read `DATA_OUT` (a live combinational mirror of
`reg_data[IDX]`, via reggen's `hwext: true`).

Version 2 used an explicit `CTRL.WR_VALID` bit (set-then-clear, edge-detected in
hardware) to commit `DATA_IN`. Version 3 replaced that with reggen's `hwqe` register
flag, which exposes the register file's own internal write-pulse (`reg2hw.data_in.qe`)
— the `DATA_IN` write itself becomes the commit, no separate strobe field needed.
That dropped one MMIO write per word (2212 → 1851 cycles) but didn't change the
fundamental shape of the problem.

**Why both were slow:** `IDX` and `DATA_IN`/`DATA_OUT` are *different* registers with a
real data dependency between them (the commit/readback needs to see the just-written
`IDX`). RISC-V's weak memory model does not guarantee MMIO writes/reads to different
addresses complete in program order — only `volatile` (which blocks compiler
reordering, not hardware/interconnect reordering) was in place initially, which
produced silently wrong results (see "pitfall" below); the fix was an explicit
`fence` after every such cross-address write. A `fence` is a real multi-cycle stall
(drains the pending AXI transaction before the next instruction issues), and with 2
fenced writes per word × 25 words each way, that stall cost dominates the whole
benchmark — worse than the duplication it was removing was ever costing.

**Pitfall worth remembering:** the very first version of this design produced
plausible-but-wrong results for a while. It looked like a hardware edge-detector race
at first glance, and a full from-scratch Verilator rebuild was done to rule out a
stale-build/caching explanation — neither was the cause. The actual bug was the
missing `fence`: `volatile` alone is not sufficient for ordering MMIO to different
addresses on this platform. Any future streaming/indexed MMIO protocol needs explicit
`fence` (or an equivalent barrier) on every cross-address dependency from the start,
not added reactively after debugging a mismatch.

## 4. Final: bulk interface, but the register file *is* the compute state

The insight that resolved the trade-off: "one copy" and "fast bulk interface" were
never actually in tension — they only looked that way because the first attempt at
"one copy" put that copy on the *core* side. Putting it on the *register-file* side
instead gets both.

`reggen`'s `hwaccess: hrw` already lets hardware drive a register's value directly
(it's what `CTRL.START`/`DONE` used from the start) — there's nothing stopping the
25-word `DATA` array from using the same mechanism. So: back to 25 independent
`DATA[i]` registers (`swaccess: rw`, `hwaccess: hrw`, generated via reggen's
`multireg`), but `keccak_dp` no longer has an internal `reg_data` at all. It became a
purely combinational round datapath plus its small control FSM: every cycle during
compute it reads `state_i` (= `reg2hw.data[i].q` for all 25 words, packed), computes
one round, and drives `state_o`/`state_we_o` back into the same 25 registers
(`hw2reg.data[i].d`/`.de`) — the register file's own flops are the pipeline register.

This preserves cycle-exact round timing versus the original (`prim_subreg`'s `q`/`wr_en`
are the same synchronous single-cycle semantics as a hand-rolled flop array — confirmed
by reading `corev_apu/register_interface/vendor/lowrisc_opentitan/src/prim_subreg.sv`
before relying on it), and restores the fully independent, fence-free bulk interface for
software — 558 cycles, matching the original's shape (2 fences total, around `START`
and after `DONE`, vs. 100 in the streaming versions).

**The one contract this adds:** software must not write any `DATA[i]` register while a
permutation is in flight (between `START` and `DONE`). Verified against
`prim_subreg_arb.sv`: for `RW`-swaccess with a simultaneous hardware `de`,
`wr_en = we | de` and `wr_data = we ? wd : d` — **software wins a same-cycle
collision**, so a stray write during compute would silently corrupt the in-flight
round. This is the same "don't touch while busy" rule the driver already had to follow
for `CTRL.START` — not a new class of risk, just extended to the data registers. The
driver enforces it by construction (loads happen before `START`, reads happen after
`DONE` is observed).

## Takeaways for the next similar loosely-coupled IP

- **Independent bus addresses don't need fences; dependent ones do.** If two registers
  have a real data dependency (one's value gates how another is interpreted, e.g. an
  index register and the data register it addresses), assume the interconnect can
  reorder them and fence explicitly. If they're truly independent, don't add
  synchronization you don't need — it's pure stall time.
- **Before adding a private copy of shared state inside a compute core, check whether
  the bus-facing register file can drive the core directly instead.** `hwaccess: hrw`
  (or `hwqe` for write-pulse detection, `hwext` for a stateless combinational
  passthrough) makes reggen's registers behave like ordinary flops from the hardware
  side — a compute engine can read/write them directly, the same way it would read/write
  its own internal array. "No duplication" doesn't have to mean "narrow streaming
  interface."
- **Measure on real RTL, not intuition.** Each of the four designs above had a
  plausible-sounding cycle-count story before it was actually run; only #4 turned out to
  hit both goals at once, and the streaming design's actual cost (fence stalls) wasn't
  obvious until measured.
