SHELL := cmd
.ONESHELL:

VIVADO   ?= vivado
PART     ?= xc7a75tfgg484-2
ROOT     := $(CURDIR)
BUILD    := $(ROOT)/build

.PHONY: default project bit synth clean distclean help

default: bit

project:
	@if not exist "$(BUILD)" mkdir "$(BUILD)"
	@echo === Creating CaptainUSB Vivado project ===
	@"$(VIVADO)" -mode batch -notrace -source scripts\create_project.tcl

bit:
	@if not exist "$(BUILD)" mkdir "$(BUILD)"
	@echo === Full bitstream build ===
	@"$(VIVADO)" -mode batch -notrace -source scripts\build_bit.tcl

synth:
	@if not exist "$(BUILD)" mkdir "$(BUILD)"
	@echo === Quick synthesis check ===
	@"$(VIVADO)" -mode batch -notrace -source scripts\check_synth.tcl

clean:
	@echo === Removing build artifacts ===
	@if exist "$(BUILD)" rmdir /s /q "$(BUILD)"

distclean: clean
	@echo === Removing IP generated files ===
	@if exist "$(ROOT)\\ip\\captainusb_pcie_7x.ip_user_files" rmdir /s /q "$(ROOT)\\ip\\captainusb_pcie_7x.ip_user_files"
	@if exist "$(ROOT)\\ip\\captainusb_pcie_7x.xgui" rmdir /s /q "$(ROOT)\\ip\\captainusb_pcie_7x.xgui"
	@if exist ".Xil" rmdir /s /q ".Xil"

help:
	@echo CaptainUSB FPGA Makefile
	@echo.
	@echo   make             - Full bitstream build ^(default^)
	@echo   make project     - Create Vivado project
	@echo   make bit         - Full bitstream build
	@echo   make synth       - Synthesis check
	@echo   make clean       - Remove build artifacts
	@echo   make distclean   - Remove build/ + IP generated files
	@echo.
	@echo   Set VIVADO env var to specify vivado path, e.g.:
	@echo     set VIVADO=D:\vivado\2025.2\Vivado\bin\vivado.bat
	@echo     make