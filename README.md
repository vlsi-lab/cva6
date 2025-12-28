# CVA6 RISC-V CPU + Keccak Accelerator
CVA6 is a 6-stage, single-issue, in-order CPU which implements the 64-bit RISC-V instruction set. It fully implements I, M, A and C extensions as specified in Volume I: User-Level ISA V 2.3 as well as the draft privilege extension 1.10. It implements three privilege levels M, S, U to fully support a Unix-like operating system. Furthermore, it is compliant to the draft external debug spec 0.13. 

This branch implements a CV-X-IF Coprocessor for Keccak acceleration, adding the following custom instructions:

- `xor3`: Three operand XOR
	- Operation: rd = rs1 ^ rs2 ^ rs3
	- Accelerates Theta (parity) step
- `xandn`: XOR-AND-Negate
	- Operation: rd = rs1 ^ (~rs2 & rs3)
	- Accelerates Chi step
- `rxri.h`/`rxri.l`: Rotate-XOR-Rotate-Immediate (High/Low): 
	- Operation: rd = ROL(rs1 ^ (rs2 ^ ROL(rs3, 1)), imm)
	- Accelerates Pi (implicit to rd), Theta and Rho steps
	- Immediate value is derived from funct2, funct3 concatenation. Since funct fields provide only 5 bit (32 possible values), the instruction is split in low and high opcodes to cover the full 64-bit rotation range

The CVA6 ID stage has been modified to support R4-type instruction formats for `CUSTOM_1`, `CUSTOM_2` and `CUSTOM_3` opcodes when offloading via CV-X-IF. This change allows the core to select directly `rs3` from the instruction rather than passing `rd` value.

# Getting Started
Clone the repository
```bash
git clone https://github.com/vlsi-lab/cva6
cd cva6
git checkout keccak-tightly
git submodule update --init --recursive
```

## Python Environment
Each user should create their own Conda environment from the provided lock file:
```bash
conda env create -f environment_lock.yml
conda activate cva6
```
That’s clean, self-contained, and clearly tied to your existing `environment_lock.yml`.


## RISC-V Toolchain and Verilator Setup 
Usually, it is strongly recommended to use the toolchain built with the provided scripts. However, to avoid redundant downloads and builds, you can use the shared prebuilt toolchain provided, modifying `cva6/verif/sim/setup-env.sh` file:

```bash
export RISCV="/software/riscv/riscv64-cva6"    
export VERILATOR_INSTALL_DIR="/software/cva6/verilator-v5.008"        ##@VLSI-Lab Server
export SPIKE_SRC_DIR="/software/cva6/riscv-isa-sim"                   ##@VLSI-Lab Server
export SPIKE_INSTALL_DIR="/software/spike/spike"                      ##@VLSI-Lab Server
export SPIKE_PATH="$SPIKE_INSTALL_DIR/bin"            
```

The shared toolchain is built from the official CVA6 scripts (util/toolchain-builder) and supports all required extensions. Users do not need to rebuild it locally unless they plan to modify or extend the toolchain itself.


### Tests
To run tests for the Keccak Coprocessor, run:
```bash
source tests/keccak/run.sh
```
A list of available tests will be printed on screen.

# Results
## KeccakF1600_StatePermute
Tests for different implementations of the coprocessor instructions were runned. The reference C code is taken from the [benchmarks of SHA3 for the RISC-V Cryptography Extension](https://github.com/riscv/riscv-crypto/blob/main/benchmarks/sha3/zscrypto_rv64/Keccak.c). All tests are runned with -O1 flag.

| Implementation | Cycles per permutation | Speedup vs baseline |
| --- | --- | --- |  
| Baseline - No ISA Extensions | 7018 | 1x | 
| Z* extensions | 5299 | 1.32x | 
| XOR3 | 5218 | 1.34x | 
| RXRI | 4483  | 1.56x | 
| XANDN | 5097 | 1.37x | 
| XOR3+RXRI+XANDN, register keyword | 3182 | 2.21x | 
| XOR3+RXRI+XANDN, asm implementation | 2469 | 2.85x |

## ML-KEM-512
To estimate performance gains in a real-world usage scenario of Keccak, Kyber512 was executed on both the Baseline ISA (rv64gc_z*) and the accelerated ISA featuring Keccak instructions.

| Implementation | Keygen CPU cycles | Encapsulation CPU cycles | Decapsulation CPU cycles |
| --- | --- | --- |  --- |  
| Baseline (-O0) | 2372223 | 5532302 | 9769437 | 
| Extern ASM Keccak_F1600StatePermute, Coprocessor (-O0) | 1856505 (1.27x)  | 4519888 (1.22x)  | 8260765 (1.18x) | 
| Baseline (-O1) | 484534  | 1102504  | 1927521 | 
| Extern ASM Keccak_F1600StatePermute, Coprocessor (-O1) | 404378 (1.19x) | 944988 (1.16x) | 1691699 (1.14x) | 

# Acknowledgements
Check out the [acknowledgements](ACKNOWLEDGEMENTS.md).