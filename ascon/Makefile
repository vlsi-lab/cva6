# Ascon Accelerator IP - Loosely
# Makefile definition for reggen

BASE_PATH = ..

REGGEN_PATH = $(BASE_PATH)/corev_apu/register_interface/vendor/lowrisc_opentitan/util/regtool.py
ASCON_IP_PATH = $(BASE_PATH)/ascon
ASCON_H_FNAME = ascon_axi.h

reg:
	python3 $(REGGEN_PATH) -r -t $(ASCON_IP_PATH)/gen/ $(ASCON_IP_PATH)/ascon.hjson
	python3 $(REGGEN_PATH) --cdefines -o $(ASCON_IP_PATH)/sw/$(ASCON_H_FNAME) $(ASCON_IP_PATH)/ascon.hjson

deps:
	pip install hjson mako
