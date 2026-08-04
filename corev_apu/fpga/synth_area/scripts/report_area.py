#!/usr/bin/env python3
"""Pull the 3-way (whole system / CVA6 core / coprocessor) area comparison
out of reports/ariane_synth_top.utilization.rpt (Vivado's
`report_utilization -hierarchical` output, see ../scripts/run_synth.tcl).

Usage: python3 report_area.py [path/to/ariane_synth_top.utilization.rpt]
"""

import re
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
DEFAULT_REPORT = SCRIPT_DIR.parent / "reports" / "ariane_synth_top.utilization.rpt"

# Instance-column values (exact match, after stripping indentation) this
# flow's area comparison is keyed off of -- see ../rtl/ariane_synth_top.sv
# for why the hierarchy looks like this.
TARGET_INSTANCES = {
    "ariane_synth_top": "Whole system (ariane_synth_top)",
    "i_cva6": "CVA6 core alone (i_cva6)",
    "gen_cvxif.gen_COPRO_KECC_AES_K.i_kecc_aes_k_xif_coprocessor": "kecc_aes_k_xif coprocessor alone",
}


def parse_hierarchical_table(report_path: Path):
    lines = report_path.read_text().splitlines()

    # Find the "Utilization by Hierarchy" table: a header row containing
    # "Instance" and "Module" between two "+---+" border lines.
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

    header = ["Metric"] + [TARGET_INSTANCES[i] for i in TARGET_INSTANCES]
    table_lines = [
        "| " + " | ".join(header) + " |",
        "|" + "|".join(["---"] * len(header)) + "|",
    ]
    for col in value_columns:
        row_vals = [matched[i][col] for i in TARGET_INSTANCES]
        table_lines.append("| " + " | ".join([col] + row_vals) + " |")

    system_luts = int(matched["ariane_synth_top"]["Total LUTs"])
    copro_luts = int(matched["gen_cvxif.gen_COPRO_KECC_AES_K.i_kecc_aes_k_xif_coprocessor"]["Total LUTs"])
    system_ffs = int(matched["ariane_synth_top"]["FFs"])
    copro_ffs = int(matched["gen_cvxif.gen_COPRO_KECC_AES_K.i_kecc_aes_k_xif_coprocessor"]["FFs"])

    summary = []
    summary.append("# ariane_synth_top area summary\n")
    summary.append(
        f"Out-of-context Vivado synthesis (`report_utilization -hierarchical`), "
        f"source: `{report_path.relative_to(SCRIPT_DIR.parent)}`.\n"
    )
    summary.extend(table_lines)
    summary.append("")
    summary.append(
        f"Coprocessor is {copro_luts}/{system_luts} = {100 * copro_luts / system_luts:.2f}% "
        f"of system Total LUTs, {copro_ffs}/{system_ffs} = {100 * copro_ffs / system_ffs:.2f}% "
        f"of system FFs."
    )

    text = "\n".join(summary) + "\n"
    print(text)

    out_path = report_path.parent / "area_summary.md"
    out_path.write_text(text)
    print(f"[report_area] wrote {out_path}", file=sys.stderr)


if __name__ == "__main__":
    main()
