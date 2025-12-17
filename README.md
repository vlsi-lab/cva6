# CVA6 RISC-V CPU + Keccak Accellerator
CVA6 is a 6-stage, single-issue, in-order CPU which implements the 64-bit RISC-V instruction set. It fully implements I, M, A and C extensions as specified in Volume I: User-Level ISA V 2.3 as well as the draft privilege extension 1.10. It implements three privilege levels M, S, U to fully support a Unix-like operating system. Furthermore, it is compliant to the draft external debug spec 0.13. 

This branch implements a CV-X-IF Coprocessor for Keccak accelleration, adding the following custom instructions:
- XOR3: three operand XOR
- XANDN: XOR-AND-Negate: implements rd = rs1 ^ (~rs2 & rs3)
- DXROLS: Dual-XOR-ROL-Single: implements rd = rs1 ^ (rs2 ^ ROL(rs3, 1))

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
Tests for different implementations of the coprocessor were runned. The reference C code is taken from the [benchmarks of SHA3 for the RISC-V Cryptography Extension](https://github.com/riscv/riscv-crypto/blob/main/benchmarks/sha3/zscrypto_rv64/Keccak.c). All tests are runned with -O1 flag.

| Implementation | Cycles for permutation | Instructions | # of ld/sd | % speedup on reference |
| --- | --- | --- |  --- |  --- |
| Reference - No ISA Extensions | 7018 | | | 0 % | 
| Z* extensions | 5299 | | | 0 % | 
| XOR3 | 5212 | | | 1.9 % | 
| DXROLS | 5077 | | | 4.2 % | 
| XANDN | 5105 | | | 4.0 % | 
| XOR3+DXROLS+XANDN, register keyword | 3785 | | | 28.7 % | 


# Acknowledgements
Check out the [acknowledgements](ACKNOWLEDGEMENTS.md).


