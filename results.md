# FALCON

This document summarizes the verification performance of **Falcon-512** and **Falcon-1024**, highlighting the impact of the NTT/INTT acceleration and the optimized rejection sampler.

## Summary

| Configuration                | Falcon-512 cycles | Falcon-512 speedup | Falcon-1024 cycles | Falcon-1024 speedup | Description                                                                                     |
| ---------------------------- | ----------------: | -----------------: | -----------------: | ------------------: | ----------------------------------------------------------------------------------------------- |
| Software baseline            |           473,803 |              1.00× |            989,144 |               1.00× | Reference verification implementation without hardware-assisted NTT/INTT or rejection sampling. |
| NTT/INTT acceleration        |           307,359 |              1.54× |            638,306 |               1.55× | Verification with accelerated forward and inverse Number-Theoretic Transforms.                  |
| NTT/INTT + rejection sampler |           230,116 |              2.06× |            490,765 |               2.02× | Verification with both NTT/INTT acceleration and the optimized rejection-sampling path.         |

## Falcon-512

| Metric                                                        |         Result | Description                                                                                          |
| ------------------------------------------------------------- | -------------: | ---------------------------------------------------------------------------------------------------- |
| Baseline verification latency                                 | 473,803 cycles | Cycle count of the original Falcon-512 verification flow.                                            |
| Verification with NTT/INTT acceleration                       | 307,359 cycles | Reduces the verification cost by 166,444 cycles, corresponding to a 1.54× speedup over the baseline. |
| Verification with NTT/INTT and rejection-sampler acceleration | 230,116 cycles | Reduces the verification cost by 243,687 cycles, corresponding to a 2.06× speedup over the baseline. |
| Additional speedup from rejection-sampler optimization        |          1.34× | Speedup relative to the NTT/INTT-only configuration.                                                 |
| `hash_to_point_vartime` before optimization                   |  80,772 cycles | Accounted for approximately 26.3% of the NTT/INTT-only verification latency.                         |
| `hash_to_point_vartime` after optimization                    |   7,989 cycles | Reduced by approximately 10.1× and accounts for about 3.5% of the final verification latency.        |

## Falcon-1024

| Metric                                                        |         Result | Description                                                                                          |
| ------------------------------------------------------------- | -------------: | ---------------------------------------------------------------------------------------------------- |
| Baseline verification latency                                 | 989,144 cycles | Cycle count of the original Falcon-1024 verification flow.                                           |
| Verification with NTT/INTT acceleration                       | 638,306 cycles | Reduces the verification cost by 350,838 cycles, corresponding to a 1.55× speedup over the baseline. |
| Verification with NTT/INTT and rejection-sampler acceleration | 490,765 cycles | Reduces the verification cost by 498,379 cycles, corresponding to a 2.02× speedup over the baseline. |
| Additional speedup from rejection-sampler optimization        |          1.30× | Speedup relative to the NTT/INTT-only configuration.                                                 |
| `hash_to_point_vartime` after optimization                    |  14,242 cycles | Accounts for approximately 2.9% of the final Falcon-1024 verification latency.                       |

## Main Observations

| Observation                         | Description                                                                                                                                                |
| ----------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Similar NTT/INTT impact             | NTT/INTT acceleration provides approximately the same improvement for both parameter sets: 1.54× for Falcon-512 and 1.55× for Falcon-1024.                 |
| Rejection sampling remains relevant | Optimizing the rejection-sampling path provides an additional 1.34× speedup for Falcon-512 and 1.30× for Falcon-1024 over the NTT/INTT-only configuration. |
| Overall verification improvement    | The combined optimizations reduce verification latency by approximately 51.4% for Falcon-512 and 50.4% for Falcon-1024.                                    |
| Reduced hashing contribution        | After optimization, `hash_to_point_vartime` represents only about 3.5% of Falcon-512 verification and 2.9% of Falcon-1024 verification.                    |

> **Speedup definition:** baseline cycle count divided by the optimized cycle count.
