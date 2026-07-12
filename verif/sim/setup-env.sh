# CVA6 project root
if [ -n "$BASH_VERSION" ]; then
  SCRIPT_PATH="$BASH_SOURCE[0]"
elif [ -n "$ZSH_VERSION" ]; then
  SCRIPT_PATH="${(%):-%N}"
else
  echo "Error: Non recognized shell."
  return
fi
export ROOT_PROJECT=$(readlink -f $(dirname "${SCRIPT_PATH}")/../..)

export RTL_PATH="$ROOT_PROJECT/"
export TB_PATH="$ROOT_PROJECT/verif/tb/core"
export TESTS_PATH="$ROOT_PROJECT/verif/tests"

# RISCV-DV & COREV-DV
export RISCV_DV_ROOT="$ROOT_PROJECT/verif/sim/dv"
export CVA6_DV_ROOT="$ROOT_PROJECT/verif/env/corev-dv"


# Set RISCV toolchain-related variables
# Respect a RISCV already exported by the caller (e.g. a personal per-machine
# setup script) instead of unconditionally clobbering it with the VLSI-Lab
# Server default below - that default doesn't exist on other machines.
if [ -z "$RISCV" ]; then
  export RISCV="/software/riscv/riscv64-cva6"                        ##@VLSI-Lab Server
fi
if [ -z "$RISCV" ]; then
  echo "Error: RISCV variable undefined."
  return
fi
#export RISCV="/home/alessandra.dolmeta/cva6/old/cva6/util/riscv_toolchain"
export LIBRARY_PATH="$RISCV/lib"
export LD_LIBRARY_PATH="$RISCV/lib:$LD_LIBRARY_PATH"
export C_INCLUDE_PATH="$RISCV/include"
export CPLUS_INCLUDE_PATH="$RISCV/include"

# Auto-detect RISC-V tool name prefix if not explicitly given.
if [ -z "$CV_SW_PREFIX" ]; then
    export CV_SW_PREFIX="$(ls -1 $RISCV/bin/riscv* | head -n 1 | rev | cut -d '/' -f 1 | cut -d '-' -f 2- | rev)-"
fi
# Default to auto-detected CC name if not explicitly given.
if [ -z "$RISCV_CC" ]; then
    export RISCV_CC="$RISCV/bin/${CV_SW_PREFIX}gcc"
fi
# Default to auto-detected OBJCOPY name if not explicitly given.
if [ -z "$RISCV_OBJCOPY" ]; then
    export RISCV_OBJCOPY="$RISCV/bin/${CV_SW_PREFIX}objcopy"
fi

# Set verilator and spike related variables
#if [ -z "$VERILATOR_INSTALL_DIR" ]; then
#    export VERILATOR_INSTALL_DIR="$ROOT_PROJECT"/tools/verilator
#fi
#if [ -z "$SPIKE_SRC_DIR" -o "$SPIKE_INSTALL_DIR" = "__local__" ]; then
#  export SPIKE_SRC_DIR="$ROOT_PROJECT"/verif/core-v-verif/vendor/riscv/riscv-isa-sim
#fi
#if [ -z "$SPIKE_INSTALL_DIR" -o "$SPIKE_INSTALL_DIR" = "__local__" ]; then
#    export SPIKE_INSTALL_DIR="$ROOT_PROJECT"/tools/spike
#fi
#export SPIKE_PATH="$SPIKE_INSTALL_DIR"/bin

# Set verilator and spike related variables
# export VERILATOR_INSTALL_DIR="$ROOT_PROJECT"/tools/verilator-v5.008
# export SPIKE_SRC_DIR="$ROOT_PROJECT"/verif/core-v-verif/vendor/riscv/riscv-isa-sim
# export SPIKE_INSTALL_DIR="$ROOT_PROJECT"/tools/spike
# export SPIKE_PATH="$SPIKE_INSTALL_DIR"/bin

# As with RISCV above, only fall back to the VLSI-Lab Server paths if the
# caller hasn't already exported these (e.g. from a personal setup script).
if [ -z "$VERILATOR_INSTALL_DIR" ]; then
    export VERILATOR_INSTALL_DIR="/software/cva6/verilator-v5.008"    ##@VLSI-Lab Server
fi
if [ -z "$SPIKE_SRC_DIR" ]; then
    export SPIKE_SRC_DIR="/software/cva6/riscv-isa-sim"               ##@VLSI-Lab Server
fi
if [ -z "$SPIKE_INSTALL_DIR" ]; then
    export SPIKE_INSTALL_DIR="/software/spike/spike"                  ##@VLSI-Lab Server
fi
export SPIKE_PATH="$SPIKE_INSTALL_DIR/bin"

# Update the PATH to add all the tools
export PATH="$VERILATOR_INSTALL_DIR/bin:$RISCV/bin:$PATH"
