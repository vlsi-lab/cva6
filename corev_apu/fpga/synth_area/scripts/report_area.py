#!/usr/bin/env python3
"""Pull the CVA6-core-vs-vrf_ip-vs-per-job-front-end area breakdown out of
reports/vrf_synth_top.utilization.rpt (Vivado's `report_utilization
-hierarchical` output, see ../scripts/run_synth.tcl).

Usage: python3 report_area.py [path/to/vrf_synth_top.utilization.rpt]
"""

import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
DEFAULT_REPORT = SCRIPT_DIR.parent / "reports" / "vrf_synth_top.utilization.rpt"

# Instance-column values (exact match, after stripping indentation/hierarchy
# whitespace) this flow's area comparison is keyed off of -- see
# ../rtl/vrf_synth_top.sv for the instance names. All vrf_ip sub-blocks are
# direct children of i_vrf_axi_top (single level deep), so no dotted path
# is needed to disambiguate them, unlike a more deeply-nested hierarchy.
TARGET_INSTANCES = {
    "vrf_synth_top": "Whole system (vrf_synth_top)",
    "i_ariane": "CVA6 core (i_ariane, incl. debug-free SoC wrapper)",
    "i_vrf_axi_top": "vrf_ip accelerator, whole (i_vrf_axi_top)",
    "vrf_reg_top_i": "  -- register file (vrf_reg_top_i)",
    "i_axi2reg": "  -- AXI-to-register-bus bridge (i_axi2reg)",
    "i_keccak": "  -- shared Keccak-f[1600] core (i_keccak)",
    "i_keccak_dma_ctrl": "  -- DMA-absorb/CSREG job (i_keccak_dma_ctrl)",
    "i_ntt_engine": "  -- NTT/iNTT job, Falcon+ML-DSA (i_ntt_engine)",
    "i_rej_sampler": "  -- rejection sampler, Falcon+ML-DSA (i_rej_sampler)",
    "i_chain_job_ctrl": "  -- SPHINCS+/SLH-DSA hash-chain job (i_chain_job_ctrl)",
    "i_falcon_decode": "  -- Falcon signature decompression (i_falcon_decode)",
    "i_falcon_normcheck": "  -- Falcon norm/bound check (i_falcon_normcheck)",
}


def parse_hierarchical_table(report_path: Path):
    lines = report_path.read_text().splitlines()

    header_idx = None
    for i, line in enumerate(lines):
        if line.startswith("|") and "Instance" in line and "Module" in line:
            header_idx = i
            break
    if header_idx is None:
        raise RuntimeError(f"Could not find the hierarchical utilization table in {report_path}")

    columns = [c.strip() for c in lines[header_idx].strip("|").split("|")]

    rows = []
    for line in lines[header_idx + 2:]:
        if not line.startswith("|"):
            break
        cells = [c.strip() for c in line.strip("|").split("|")]
        if len(cells) != len(columns):
            continue
        rows.append(dict(zip(columns, cells)))
    return columns, rows


def main():
    report_path = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_REPORT
    if not report_path.is_file():
        sys.exit(f"error: {report_path} not found -- run ./run_synth.sh first")

    columns, rows = parse_hierarchical_table(report_path)
    value_columns = [c for c in columns if c not in ("Instance", "Module")]

    matched = {}
    for row in rows:
        instance = row["Instance"]
        if instance in TARGET_INSTANCES and instance not in matched:
            matched[instance] = row

    missing = [i for i in TARGET_INSTANCES if i not in matched]
    if missing:
        sys.exit(f"error: instance(s) not found in {report_path}: {missing}")

    order = list(TARGET_INSTANCES)
    header = ["Metric"] + [TARGET_INSTANCES[i] for i in order]
    table_lines = [
        "| " + " | ".join(header) + " |",
        "|" + "|".join(["---"] * len(header)) + "|",
    ]
    for col in value_columns:
        row_vals = [matched[i][col] for i in order]
        table_lines.append("| " + " | ".join([col] + row_vals) + " |")

    system_luts = int(matched["vrf_synth_top"]["Total LUTs"])
    system_ffs = int(matched["vrf_synth_top"]["FFs"])
    core_luts = int(matched["i_ariane"]["Total LUTs"])
    core_ffs = int(matched["i_ariane"]["FFs"])
    vrf_luts = int(matched["i_vrf_axi_top"]["Total LUTs"])
    vrf_ffs = int(matched["i_vrf_axi_top"]["FFs"])

    summary = []
    summary.append("# vrf_synth_top area summary\n")
    summary.append(
        f"Out-of-context Vivado synthesis (`report_utilization -hierarchical`), "
        f"source: `{report_path.relative_to(SCRIPT_DIR.parent)}`.\n"
    )
    summary.extend(table_lines)
    summary.append("")
    summary.append(
        f"vrf_ip is {vrf_luts}/{system_luts} = {100 * vrf_luts / system_luts:.2f}% "
        f"of system Total LUTs, {vrf_ffs}/{system_ffs} = {100 * vrf_ffs / system_ffs:.2f}% "
        f"of system FFs -- the CVA6 core alone (i_ariane) is "
        f"{100 * core_luts / system_luts:.2f}% of Total LUTs, "
        f"{100 * core_ffs / system_ffs:.2f}% of FFs."
    )
    summary.append(
        "\nWithin vrf_ip, sub-block share of vrf_ip's own Total LUTs:"
    )
    for inst in TARGET_INSTANCES:
        if inst in ("vrf_synth_top", "i_ariane", "i_vrf_axi_top"):
            continue
        luts = int(matched[inst]["Total LUTs"])
        summary.append(f"- {TARGET_INSTANCES[inst].strip('- ')}: {luts} LUTs ({100 * luts / vrf_luts:.1f}%)")

    text = "\n".join(summary) + "\n"
    print(text)

    out_path = report_path.parent / "area_summary.md"
    out_path.write_text(text)
    print(f"[report_area] wrote {out_path}", file=sys.stderr)


if __name__ == "__main__":
    main()