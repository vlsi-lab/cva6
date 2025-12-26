# Keccak Accelerator IP
WIP...

## Directory tree
WIP...

## Patchlist
- core/include/config_pkg.sv: add COPRO_KECCAK in copro_type_t
- core/include/build_config_pkg.sv enable 3 read ports
- core/include/cv64a6_imafdc_sv39_config_pkg.sv: set coprocessor type as COPRO_KECCAK
- core/Flist.cva6: add kekkak coprocessor files
- corev_apu/src/ariane.sv: instantiate coprocessor
