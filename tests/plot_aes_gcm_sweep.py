#!/usr/bin/env python3
"""Figure for the paper: AES-128-GCM speedup vs. payload size.

Reads aes_gcm_sweep_data.csv (produced from tests/software/aes_gcm_sweep and
tests/tightly/aes_gcm_sweep's real veri-testharness output -- see
tests/result.md's "Results -- AES-GCM payload-size sweep" for the runs this
data comes from) and writes aes_gcm_sweep.pdf/.png: a single plot, cycles on
the left y-axis (log) and speedup on the right y-axis (linear), payload size
on a log x-axis. Decrypt only -- encrypt tracks it closely enough (see the
printed table below, or tests/result.md) that showing both would just be two
overlapping pairs of lines; the text/caption should say encrypt behaves the
same.

Usage: python3 plot_aes_gcm_sweep.py [csv_path] [output_basename]
"""

import csv
import sys
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

SCRIPT_DIR = Path(__file__).resolve().parent
DEFAULT_CSV = SCRIPT_DIR / "aes_gcm_sweep_data.csv"
DEFAULT_OUT = SCRIPT_DIR / "aes_gcm_sweep"


def load_data(csv_path: Path):
    rows = []
    with open(csv_path, newline="") as f:
        for row in csv.DictReader(f):
            rows.append({k: int(v) for k, v in row.items()})
    rows.sort(key=lambda r: r["size_bytes"])
    return rows


def main():
    csv_path = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_CSV
    out_base = Path(sys.argv[2]) if len(sys.argv) > 2 else DEFAULT_OUT

    if not csv_path.is_file():
        sys.exit(f"error: {csv_path} not found")

    rows = load_data(csv_path)
    sizes = [r["size_bytes"] for r in rows]

    sw_enc = [r["sw_encrypt_cycles"] for r in rows]
    sw_dec = [r["sw_decrypt_cycles"] for r in rows]
    hw_enc = [r["tightly_encrypt_cycles"] for r in rows]
    hw_dec = [r["tightly_decrypt_cycles"] for r in rows]

    speedup_enc = [s / h for s, h in zip(sw_enc, hw_enc)]
    speedup_dec = [s / h for s, h in zip(sw_dec, hw_dec)]

    sw_color = "#d95f02"
    hw_color = "#1b9e77"
    speedup_color = "#7570b3"

    fig, ax_cycles = plt.subplots(figsize=(7, 5))

    # --- Left axis: cycles, log ---
    l1, = ax_cycles.plot(sizes, sw_dec, "o-", color=sw_color, label="Software (cycles)")
    l2, = ax_cycles.plot(sizes, hw_dec, "s-", color=hw_color, label="Accelerated (cycles)")
    ax_cycles.set_xscale("log", base=2)
    ax_cycles.set_yscale("log")
    ax_cycles.set_xlabel("Payload size (bytes)")
    ax_cycles.set_ylabel("Cycles")
    ax_cycles.grid(True, which="both", linestyle=":", linewidth=0.6)

    # --- Right axis: speedup, linear, tight range (not zeroed: speedup
    # stays in a narrow ~12.8-13.8x band -- forcing the axis to include 0
    # would flatten the actual small-size-vs-plateau trend this figure
    # exists to show, see tests/result.md) ---
    ax_speedup = ax_cycles.twinx()
    l3, = ax_speedup.plot(sizes, speedup_dec, "^--", color=speedup_color, label="Speedup (right axis)")
    ax_speedup.set_ylabel("Speedup (software cycles / accelerated cycles)", color=speedup_color)
    ax_speedup.tick_params(axis="y", labelcolor=speedup_color)
    margin = 0.3
    ax_speedup.set_ylim(min(speedup_dec) - margin, max(speedup_dec) + margin)

    ax_cycles.legend(handles=[l1, l2, l3], fontsize=8, loc="upper left")

    ax_cycles.set_title(
        "AES-128-GCM decrypt: cycles and speedup vs. payload size\n"
        "Fixed 20 B AAD, kecc_aes_k_xif (AES) + native clmul/clmulh (GHASH)\n"
        "(encrypt behaves the same -- within 1% of decrypt at every size, see tests/result.md)",
        fontsize=9.5,
    )
    fig.tight_layout()

    fig.savefig(f"{out_base}.pdf")
    fig.savefig(f"{out_base}.png", dpi=200)
    print(f"Wrote {out_base}.pdf and {out_base}.png")

    print("\nsize_bytes  sw_enc  hw_enc  speedup_enc   sw_dec  hw_dec  speedup_dec")
    for r, se, sd in zip(rows, speedup_enc, speedup_dec):
        print(f"{r['size_bytes']:>10}  {r['sw_encrypt_cycles']:>6}  {r['tightly_encrypt_cycles']:>6}  "
              f"{se:>10.2f}x  {r['sw_decrypt_cycles']:>6}  {r['tightly_decrypt_cycles']:>6}  {sd:>10.2f}x")


if __name__ == "__main__":
    main()
