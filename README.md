# CVA6 RISC-V CPU + Keccak Accelerator
CVA6 is a 6-stage, single-issue, in-order CPU which implements the 64-bit RISC-V instruction set. It fully implements I, M, A and C extensions as specified in Volume I: User-Level ISA V 2.3 as well as the draft privilege extension 1.10. It implements three privilege levels M, S, U to fully support a Unix-like operating system. Furthermore, it is compliant to the draft external debug spec 0.13. 

This branch implements a coprocessor for Keccak acceleration instantiated in the AXI-4 crossbar. By default its base address is set to ```0x50000000``` and it exposes 25 registers for the cryptographic state and one Control/Status register.

The mapping of the accellerator is the following:
| Register Name | Offset | Width | Description | Fields |
|--------------|--------|-------|-------------|--------|
| DATA_0 - DATA_24 | 0x00 - 0xC0 | 64 bit | I/O cryptographic state registers (25 registers, 8 byte stride) | DATA[63:0] |
| CSREG | 0xC8 | 64 bit | Control and status register | START[0], DONE[1], others unused |


This work has been developed for the Integrated Systems Architecture course special project at Politecnico di Torino.
# Getting Started
Clone the repository
```bash
git clone https://github.com/vlsi-lab/cva6
cd cva6
git checkout keccak-loosely
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

## Register and header files generation 
To generate register definitions and their relative header file for the Keccak coprocessor, run ```make reg``` in the ```./keccak_ip``` folder. The generated files are located for RTL in ```./keccak_ip/gen``` and for the C Header file in ```./keccak_ip/sw```

## Tests
To run tests for the Keccak Coprocessor, issue:
```bash
source tests/keccak/run.sh
```
A list of available tests will be printed on screen.

To run Kyber512 tests, issue:
```bash
source tests/ml-kem-512/run.sh
source tests/ml-kem-512/run.sh copro
```
Depending on wether you want to simulate Kyber tests with or without the coprocessor.

# Results
## veri-testharness
### KeccakF1600_StatePermute
Tests for different implementations of the coprocessor instructions were runned. The reference C code is taken from the [benchmarks of SHA3 for the RISC-V Cryptography Extension](https://github.com/riscv/riscv-crypto/blob/main/benchmarks/sha3/zscrypto_rv64/Keccak.c). All tests are runned with -O2 flag.

| Implementation | Cycles per permutation | Speedup vs baseline |
| --- | --- | --- |  
| Baseline - No ISA Extensions | 8031 | 1x | 
| AXI Coprocessor | 493 | 16.29x |


## ML-KEM-512
To estimate performance gains in a real-world usage scenario of Keccak, Kyber512 was executed on both the Baseline ISA (rv64imac_zicsr_zifencei) and the CPU with the Keccak accellerator

| Implementation | Keygen CPU cycles | Encapsulation CPU cycles | Decapsulation CPU cycles |
| --- | --- | --- |  --- |  
| Baseline - No ISA Extensions (-O2) | 573784 | 712582 | 917591 | 
| AXI Coprocessor (-O2) | 335202 (1.71x)  | 483173 (1.48x)  | 688285 (1.33x) | 

## Hardware Validation on CW305 board
To validate the design in a real-world environment, the system was synthesized and deployed on the CW305 FPGA. The integration of the accellerator into the CVA6 required 7091 LEs, representing a 18.6% overhead on the CPU total area of 38081 LEs. The HW implementations instantiates a 512 KB SRAM that increases the memory latency compared to the simulation environment, resulting in different speedups compared to the simulation.
### KeccakF1600_StatePermute
| Implementation | Cycles per permutation | Speedup vs baseline |
| --- | --- | --- |  
| Baseline - No ISA Extensions (-O2) | 11126 | 1x | 
| AXI Coprocessor (-O2) | 839 | 13.26x |

### ML-KEM-512
| Implementation | Keygen CPU cycles | Encapsulation CPU cycles | Decapsulation CPU cycles |
| --- | --- | --- |  --- |  
| Baseline (-O2) | 756712 | 882759 | 1114188 | 
| Extern ASM Keccak_F1600StatePermute, Coprocessor (-O2) | 399422 (1.89x) | 539382 (1.64x) | 771085 (1.44x) | 

# Acknowledgements
Check out the [acknowledgements](ACKNOWLEDGEMENTS.md).