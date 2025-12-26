# Ghidra support for the Keccak Coprocessor

## Installation
- Locate install folder of Ghidra
- Copy riscv.keccak.sinc in GHIDRA_DIR/Ghidra/Processors/RISCV/data/languages/
- Edit GHIDRA_DIR/Ghidra/Processors/RISCV/data/languages/riscv.lp64d.slaspec and add at the end of the file 
```bash
@include "riscv.keccak.sinc"
```
- Edit GHIDRA_DIR/Ghidra/Processors/RISCV/data/languages/riscv.instr.sinc and comment out 
```bash
@include "riscv.custom.sinc"
```

- Recompile language definition:
```bash
./support/sleigh Ghidra/Processors/RISCV/data/languages/riscv.lp64d.slaspec
```
- Restart Ghidra

If when opening CodeBrowser Ghidra hangs on the dragon window, delete the local .ghidra directory and restart Ghidra
