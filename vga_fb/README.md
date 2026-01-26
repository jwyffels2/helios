# VGA Framebuffer / VRAM Integration (Scaffold)

Status: scaffold only. This work is additive and does NOT replace the main
NEORV32 top-level, constraints, or build flow.

Current state:
- New RTL blocks exist but are not wired into `rtl/helios.vhdl` yet.
- No constraint changes are required or included for the framebuffer work.
- Build scripts remain the main flow; no VGA-only build path is introduced.

What exists now:
- `rtl/vram_rgb332_dp.vhd`: byte-addressed VRAM with 32-bit write + byte enables
  and 1-byte VGA read path (RGB332).
- `rtl/vram_wb_slave.vhd`: Wishbone-style shim for a future NEORV32 bus link.
- `rtl/vga_640x480_timing.vhd`: timing-only generator (pixel strobe model).
- `src/vga_fb.ads` / `src/vga_fb.adb`: Ada stubs for a 160x120 RGB332 framebuffer.
- `vga_fb/vhdl/*`: interface/VRAM stubs for documenting intended wiring.
- `rtl/program_board.tcl`: helper to program the newest bitstream (optional).

What is NOT done yet:
- No top-level integration of VRAM or VGA scanout.
- No verified end-to-end VGA output from framebuffer contents.
- No validated address map in hardware (only documented intent).
- No camera/DMA capture logic.

Next steps (expected):
- Wire VRAM and bus shim into the NEORV32 top-level.
- Decide address map and document it in VHDL + Ada consistently.
- Add integration tests (write pattern in SW, observe VGA output).
