# ariane_synth_top area summary

Out-of-context Vivado synthesis (`report_utilization -hierarchical`), source: `reports/ariane_synth_top.utilization.rpt`.

| Metric | Whole system (ariane_synth_top) | CVA6 core alone (i_cva6) | kecc_aes_k_xif coprocessor alone |
|---|---|---|---|
| Total LUTs | 56001 | 55452 | 375 |
| Logic LUTs | 56001 | 55452 | 375 |
| LUTRAMs | 0 | 0 | 0 |
| SRLs | 0 | 0 | 0 |
| FFs | 23889 | 23623 | 265 |
| RAMB36 | 36 | 36 | 0 |
| RAMB18 | 0 | 0 | 0 |
| DSP Blocks | 27 | 27 | 0 |

Coprocessor is 375/56001 = 0.67% of system Total LUTs, 265/23889 = 1.11% of system FFs.
