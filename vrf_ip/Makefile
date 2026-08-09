# VRF Accelerator IP - Loosely
# Makefile definition for reggen
# Author: Federico Runco

BASE_PATH = ..

REGGEN_PATH = $(BASE_PATH)/corev_apu/register_interface/vendor/lowrisc_opentitan/util/regtool.py
VRF_IP_PATH = $(BASE_PATH)/vrf_ip
VRF_H_FNAME = vrf_axi.h

reg:
	python3 $(REGGEN_PATH) -r -t $(VRF_IP_PATH)/gen/ $(VRF_IP_PATH)/vrf.hjson
	python3 $(REGGEN_PATH) --cdefines -o $(VRF_IP_PATH)/sw/$(VRF_H_FNAME) $(VRF_IP_PATH)/vrf.hjson

deps:
	pip install hjson mako
