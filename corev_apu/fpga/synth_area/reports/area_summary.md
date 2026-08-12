# vrf_synth_top area summary

Out-of-context Vivado synthesis (`report_utilization -hierarchical`), source: `reports/vrf_synth_top.utilization.rpt`.

| Metric | Whole system (vrf_synth_top) | CVA6 core (i_ariane, incl. debug-free SoC wrapper) | vrf_ip accelerator, whole (i_vrf_axi_top) |   -- register file (vrf_reg_top_i) |   -- AXI-to-register-bus bridge (i_axi2reg) |   -- shared Keccak-f[1600] core (i_keccak) |   -- DMA-absorb/CSREG job (i_keccak_dma_ctrl) |   -- NTT/iNTT job, Falcon+ML-DSA (i_ntt_engine) |   -- rejection sampler, Falcon+ML-DSA (i_rej_sampler) |   -- SPHINCS+/SLH-DSA hash-chain job (i_chain_job_ctrl) |   -- Falcon signature decompression (i_falcon_decode) |   -- Falcon norm/bound check (i_falcon_normcheck) |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Total LUTs | 70402 | 52966 | 17436 | 1680 | 2853 | 6295 | 510 | 1723 | 424 | 3391 | 277 | 283 |
| Logic LUTs | 70402 | 52966 | 17436 | 1680 | 2853 | 6295 | 510 | 1723 | 424 | 3391 | 277 | 283 |
| LUTRAMs | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| SRLs | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| FFs | 33577 | 23607 | 9969 | 3552 | 672 | 1631 | 149 | 1690 | 215 | 1587 | 241 | 230 |
| RAMB36 | 37 | 36 | 1 | 0 | 0 | 0 | 0 | 1 | 0 | 0 | 0 | 0 |
| RAMB18 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| DSP Blocks | 33 | 27 | 6 | 0 | 0 | 0 | 0 | 4 | 0 | 0 | 0 | 2 |

vrf_ip is 17436/70402 = 24.77% of system Total LUTs, 9969/33577 = 29.69% of system FFs -- the CVA6 core alone (i_ariane) is 75.23% of Total LUTs, 70.31% of FFs.

Within vrf_ip, sub-block share of vrf_ip's own Total LUTs:
- register file (vrf_reg_top_i): 1680 LUTs (9.6%)
- AXI-to-register-bus bridge (i_axi2reg): 2853 LUTs (16.4%)
- shared Keccak-f[1600] core (i_keccak): 6295 LUTs (36.1%)
- DMA-absorb/CSREG job (i_keccak_dma_ctrl): 510 LUTs (2.9%)
- NTT/iNTT job, Falcon+ML-DSA (i_ntt_engine): 1723 LUTs (9.9%)
- rejection sampler, Falcon+ML-DSA (i_rej_sampler): 424 LUTs (2.4%)
- SPHINCS+/SLH-DSA hash-chain job (i_chain_job_ctrl): 3391 LUTs (19.4%)
- Falcon signature decompression (i_falcon_decode): 277 LUTs (1.6%)
- Falcon norm/bound check (i_falcon_normcheck): 283 LUTs (1.6%)
