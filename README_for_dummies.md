source verif/sim/setup-env.sh 
conda activate cva6
git submodule update --init --recursive
make fpga BOARD=cw305