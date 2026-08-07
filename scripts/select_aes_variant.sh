#!/bin/bash
# Maps the single AES_VARIANT flag to the two things a tests/loosely/<name>/run.sh
# needs before calling verif/sim/cva6.py: which CVA6 target config to build
# (DV_TARGET/TARGET_CFG) and which kecc_aes_k_axi/hw/rtl/vN/ RTL variant
# core/Flist.cva6 should compile in (AES_LOOSE_VERSION). Simulation and Vivado
# synthesis both read core/Flist.cva6 the same way, so exporting these two vars
# before either flow picks the same accelerator for both.
#
# Usage: AES_VARIANT=loose_v2 source ./scripts/select_aes_variant.sh
#
# sw/ise are not routed through here -- tests/software/ and tests/tightly/
# already hardcode DV_TARGET=cv64a6_imafdc_sv39 in their own run.sh and don't
# touch the loosely-coupled accelerator, so there is nothing for this script
# to select for them.
#
# DV_TARGET must be a name cva6.py's own --target whitelist recognizes (it
# derives --mabi/--isa from it); TARGET_CFG is the actual
# core/include/<...>_config_pkg.sv compiled in (see core/Flist.cva6). These
# are deliberately different for every loose_* case below -- none of the
# per-version/per-SBOX_IMPL config names are in cva6.py's whitelist, so
# DV_TARGET always stays cv64a6_imac_crypto (same rv64imac/lp64 ABI as every
# loose_* config, all copied from the same base) while TARGET_CFG picks the
# real config. Exporting TARGET_CFG here (rather than relying on Makefile's
# `ifndef TARGET_CFG; export TARGET_CFG = $(target)` fallback) is what makes
# the two diverge.

if [ -z "$AES_VARIANT" ]; then
    echo "select_aes_variant.sh: AES_VARIANT is not set." >&2
    echo "  Valid values: loose_v2, loose_v3," >&2
    echo "  loose_v4_serial_rom, loose_v4_dp_rom, loose_v4_bp," >&2
    echo "  loose_v5_serial_rom, loose_v5_dp_rom, loose_v5_bp." >&2
    return 1 2>/dev/null || exit 1
fi

export DV_TARGET=cv64a6_imac_crypto

case "$AES_VARIANT" in
    loose_v2)
        export TARGET_CFG=cv64a6_imac_crypto_loose_v2
        export AES_LOOSE_VERSION=v2
        ;;
    loose_v3)
        export TARGET_CFG=cv64a6_imac_crypto_loose_v3
        export AES_LOOSE_VERSION=v3
        ;;
    loose_v4_serial_rom)
        export TARGET_CFG=cv64a6_imac_crypto_loose_v4_serial_rom
        export AES_LOOSE_VERSION=v4
        ;;
    loose_v4_dp_rom)
        export TARGET_CFG=cv64a6_imac_crypto_loose_v4_dp_rom
        export AES_LOOSE_VERSION=v4
        ;;
    loose_v4_bp)
        export TARGET_CFG=cv64a6_imac_crypto_loose_v4_bp
        export AES_LOOSE_VERSION=v4
        ;;
    loose_v5_serial_rom)
        export TARGET_CFG=cv64a6_imac_crypto_loose_v5_serial_rom
        export AES_LOOSE_VERSION=v5
        ;;
    loose_v5_dp_rom)
        export TARGET_CFG=cv64a6_imac_crypto_loose_v5_dp_rom
        export AES_LOOSE_VERSION=v5
        ;;
    loose_v5_bp)
        export TARGET_CFG=cv64a6_imac_crypto_loose_v5_bp
        export AES_LOOSE_VERSION=v5
        ;;
    *)
        echo "select_aes_variant.sh: unknown AES_VARIANT '$AES_VARIANT'" >&2
        return 1 2>/dev/null || exit 1
        ;;
esac
