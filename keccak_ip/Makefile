# Keccak Accelerator IP - Loosely
# Makefile definition for reggen
# Author: Federico Runco

BASE_PATH = ..

REGGEN_PATH = $(BASE_PATH)/corev_apu/register_interface/vendor/lowrisc_opentitan/util/regtool.py
KECCAK_IP_PATH = $(BASE_PATH)/keccak_ip
KECCAK_H_FNAME = keccak_axi.h

reg:
	python3 $(REGGEN_PATH) -r -t $(KECCAK_IP_PATH)/gen/ $(KECCAK_IP_PATH)/keccak.hjson 
	python3 $(REGGEN_PATH) --cdefines -o $(KECCAK_IP_PATH)/sw/$(KECCAK_H_FNAME) $(KECCAK_IP_PATH)/keccak.hjson

deps:
	pip install hjson mako