# kecc_aes_k_axi (v2) - Loosely coupled AXI wrapper
# Makefile definition for reggen

BASE_PATH = ../../..

REGGEN_PATH = $(BASE_PATH)/corev_apu/register_interface/vendor/lowrisc_opentitan/util/regtool.py
REGS_PATH = $(BASE_PATH)/kecc_aes_k_axi/hw/regs
SW_PATH = $(BASE_PATH)/kecc_aes_k_axi/sw
REGS_H_FNAME = kecc_aes_k_axi_regs.h

reg:
	python3 $(REGGEN_PATH) -r -t $(REGS_PATH)/gen/ $(REGS_PATH)/kecc_aes_k_axi.hjson
	python3 $(REGGEN_PATH) --cdefines -o $(SW_PATH)/$(REGS_H_FNAME) $(REGS_PATH)/kecc_aes_k_axi.hjson
	python3 $(REGGEN_PATH) -r -t $(REGS_PATH)/gen/ $(REGS_PATH)/kecc_aes_k_axi_unified.hjson
	python3 $(REGGEN_PATH) --cdefines -o $(SW_PATH)/kecc_aes_k_axi_unified_regs.h $(REGS_PATH)/kecc_aes_k_axi_unified.hjson

deps:
	pip install hjson mako
