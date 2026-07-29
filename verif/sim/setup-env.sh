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
export RISCV="/home/aledolme/tools/riscv64"                           ##@Local
if [ -z "$RISCV" ]; then
  echo "Error: RISCV variable undefined."
  return
fi
#export RISCV="/home/alessandra.dolmeta/cva6/old/cva6/util/riscv_toolchain"
export LIBRARY_PATH="$RISCV/lib"
export LD_LIBRARY_PATH="$RISCV/lib:$LD_LIBRARY_PATH"
export C_INCLUDE_PATH="$RISCV/include"
export CPLUS_INCLUDE_PATH="$RISCV/include"

# Always re-derive prefix and tool paths from $RISCV so stale env vars never
# survive across re-sources with a different RISCV path.
export CV_SW_PREFIX="$(ls -1 $RISCV/bin/riscv* | head -n 1 | rev | cut -d '/' -f 1 | cut -d '-' -f 2- | rev)-"
export RISCV_CC="$RISCV/bin/${CV_SW_PREFIX}gcc"
export RISCV_OBJCOPY="$RISCV/bin/${CV_SW_PREFIX}objcopy"

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

export VERILATOR_INSTALL_DIR="/home/aledolme/tools/verilator-v5.008"  ##@Local
export SPIKE_SRC_DIR="$ROOT_PROJECT/verif/core-v-verif/vendor/riscv/riscv-isa-sim"
export SPIKE_INSTALL_DIR="/home/aledolme/tools/spike"                 ##@Local
export SPIKE_PATH="$SPIKE_INSTALL_DIR/bin"

# Update the PATH to add all the tools
export PATH="$VERILATOR_INSTALL_DIR/bin:$RISCV/bin:$PATH"
