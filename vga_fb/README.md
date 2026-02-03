# VGA Framebuffer / VRAM Integration (WIP)

Status: WIP. This work is additive and does NOT replace the main NEORV32
top-level, constraints, or build flow.

Current state:
- The building blocks exist and use HELIOS/NEORV32-friendly conventions
  (`std_ulogic` + active-low reset `rstn_i`).
- The blocks are not wired into `rtl/helios.vhdl` yet.
- No VGA pin constraints are included yet (you will need to add them).

What exists now:
- `rtl/vram_rgb332_dp.vhd`: byte-addressed VRAM (RGB332) with 32-bit writes +
  byte enables and a 1-byte VGA read port (1-cycle latency).
- `rtl/vram_wb_slave.vhd`: NEORV32 XBUS / Wishbone-like write-only window at
  `0xF000_0000` (latches requests so it works with XBUS STB pulsing).
- `rtl/vga_640x480_timing.vhd`: VGA 640x480 timing generator with internal pixel
  clock-enable divider (`PIX_CE_DIV` generic, default 4 for 100 MHz -> 25 MHz).
- `vga_fb/vhdl/fb_if.vhd`: convenience wrapper that instantiates the WB slave +
  VRAM and provides a simple scanout mapping (640x480 -> 160x120 via x>>2/y>>2).
- `src/vga_fb.ads` / `src/vga_fb.adb`: minimal Ada MMIO API (byte pixel writes +
  32-bit fill) with base address `0xF000_0000`.
- `rtl/program_board.tcl`: helper to program the newest bitstream (optional).

What is NOT done yet:
- No top-level integration of VRAM/VGA scanout in `rtl/helios.vhdl`.
- No verified end-to-end VGA output (needs top-level wiring + XDC pins).
- No readback path (bus reads currently return 0s).
- No camera/DMA capture logic.

Expected integration steps:
- Enable NEORV32 XBUS (`XBUS_EN => true`) in `rtl/helios.vhdl` and connect the
  `xbus_*` signals to `vga_fb/vhdl/fb_if.vhd` (or directly to `rtl/vram_wb_slave.vhd`).
- Add VGA output pins to your `.xdc` and implement DAC/resistor wiring as needed.
