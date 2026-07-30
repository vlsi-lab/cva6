# GF(2) multiply-reduce Accelerator IP
# Makefile definition for reggen -- mirrors keccak_ip/Makefile

BASE_PATH = ..

REGGEN_PATH = $(BASE_PATH)/corev_apu/register_interface/vendor/lowrisc_opentitan/util/regtool.py
GF2_IP_PATH = $(BASE_PATH)/gf2_ip
GF2_H_FNAME = gf2_axi.h

reg:
	python3 $(REGGEN_PATH) -r -t $(GF2_IP_PATH)/gen/ $(GF2_IP_PATH)/gf2.hjson
	python3 $(REGGEN_PATH) --cdefines -o $(GF2_IP_PATH)/sw/$(GF2_H_FNAME) $(GF2_IP_PATH)/gf2.hjson

deps:
	pip install hjson mako
