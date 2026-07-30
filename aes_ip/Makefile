# AES-128 Accelerator IP
# Makefile definition for reggen -- mirrors keccak_ip/Makefile

BASE_PATH = ..

REGGEN_PATH = $(BASE_PATH)/corev_apu/register_interface/vendor/lowrisc_opentitan/util/regtool.py
AES_IP_PATH = $(BASE_PATH)/aes_ip
AES_H_FNAME = aes_axi.h

reg:
	python3 $(REGGEN_PATH) -r -t $(AES_IP_PATH)/gen/ $(AES_IP_PATH)/aes.hjson
	python3 $(REGGEN_PATH) --cdefines -o $(AES_IP_PATH)/sw/$(AES_H_FNAME) $(AES_IP_PATH)/aes.hjson

deps:
	pip install hjson mako
