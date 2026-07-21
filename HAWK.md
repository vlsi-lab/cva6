# HAWK Measurement Results

## Measurement Configuration

| Item | Value |
|---|---|
| Processor | CVA6 |
| ISA | RISC-V |
| Implementation | Pure software (C) |
| Algorithm | HAWK |
| Variants tested | HAWK-256, HAWK-512, HAWK-1024 |
| Metric | Clock cycles |
| HW acceleration | None |

## Keccak/SHAKE Calls — HAWK-256

| Operation | Keccak Calls |
|---|---:|
| KeyGen | 148 |
| Sign | 47 |
| Verify | 6 |

## Cycle Measurements

| Variant | KeyGen (cycles) | Sign (cycles) | Verify (cycles) 
|---|---:|---:|---:| 
| HAWK-256 | 9,948,715 | 849,512 | 606,729 | 
| HAWK-256 (Keccak) | 8,814,424 [x1.29] | 493,923 [x1.71] | 561,447 [x1.08] 

| HAWK-512 | 72,160,003 | 1,718,456 | 1,259,961 | 
| HAWK-512 (Keccak) | 691,72,595 | 1,057,640 | 1,185,323 |
| HAWK-1024 | 226,285,877 | 3,754,767 | 2,703,933 | 
| HAWK-1024 (Keccak) |  |  |  |


Started 1 test(s) - Hawk-256
Test 0:
Clock cycles [keygen]: 8798037
Keygen OK
Clock cycles [sign]: 494313
Sign OK
Clock cycles [verify]: 561971