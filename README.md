# helios

Open-source wildfire detection CubeSat project.

This repo currently contains:
- An FPGA SoC top-level for Digilent Basys3 based on NEORV32: `rtl/helios.vhdl`
- Ada firmware (Alire project): `src/`

## FPGA (Vivado / Basys3)

Top-level: `rtl/helios.vhdl` (entity `helios`).

Build + program (Windows):
```powershell
.\build_neorv32.bat --create
```

Manual Vivado flow:
```powershell
cd rtl
vivado -mode batch -source build.tcl
vivado -mode batch -source program_board.tcl
```

Notes:
- `rtl/build.tcl` recreates/cleans `rtl/work/`.
- `rtl/program_board.tcl` finds and programs the newest `helios.bit` under `rtl/work/`.
- I/O pin mapping for the Basys3 setup lives in `rtl/basys3_a7_test_setup.xdc`.

## Firmware (Ada / Alire)

The provided container build (Podman) produces a NEORV32 bootloader-compatible image (`bin/helios.exe`):
```powershell
podman build -t helios-build -f ./build.dockerfile .
podman run --rm -it -v "%CD%:/workspace" -w /workspace helios-build ./build_hal_fw.sh
```

There is also a convenience wrapper: `build.bat`.

## VGA framebuffer (WIP)

This repo includes RGB332 framebuffer building blocks intended to be wired into `rtl/helios.vhdl` via the NEORV32 XBUS:
- Base address: `0xF000_0000` (see `src/vga_fb.ads`)
- RTL: `rtl/vram_rgb332_dp.vhd`, `rtl/vram_wb_slave.vhd`, `rtl/vga_640x480_timing.vhd`
- Wrapper: `vga_fb/vhdl/fb_if.vhd`

VGA output is not enabled by default (top-level wiring + XDC pins still required).

## Getting started

Environment setup (Podman/Alire/WSL): `docs/Getting_Started.md`
