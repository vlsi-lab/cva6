#!/bin/bash
############################################
# ----- INITIALIZE cva6 ENVIRONMENT ----- #
############################################

function init_cva6() {

    echo "--------------------------------------------"
    echo " Activating Conda environment: cva6"
    echo "--------------------------------------------"

    # Activate Conda environment (safe for both login and non-login shells)
    if command -v conda >/dev/null 2>&1; then
        eval "$(conda shell.bash hook)"
        conda activate cva6
    else
        echo "Error: conda not found. Please ensure Conda is installed and available in PATH."
        return 1
    fi

}

# Run setup
init_cva6 "$@"
