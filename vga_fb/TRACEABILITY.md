# Traceability Notes (VGA Framebuffer / VRAM)

Context:
- The main branch keeps a NEORV32 top-level with UART/GPIO/PWM and build flow.
- VGA signal work exists elsewhere; this branch does not replace it.
- This branch focuses on a CPU-writable VRAM path that can drive VGA later.

In-scope for this change set:
- VRAM storage with byte-enable writes and VGA read path (`rtl/vram_rgb332_dp.vhd`).
- A simple Wishbone-style shim for future NEORV32 external bus integration
  (`rtl/vram_wb_slave.vhd`).
- A timing-only VGA generator for later use (`rtl/vga_640x480_timing.vhd`).
- Ada stubs that express the intended software API (`src/vga_fb.*`).
- Documentation stubs describing the intended integration points.

Out-of-scope / intentionally unchanged:
- No replacement of the NEORV32 top-level or build scripts.
- No constraint changes for VGA pins.
- No end-to-end VGA scanout from VRAM in this branch.
- No camera, DMA, or display pipeline changes.

Addressing intent (documented only):
- VRAM window base: 0xF000_0000 (see `vram_wb_slave`).
- Size: 0x5000 bytes (19200 bytes used for 160x120 RGB332).
- Ada stubs currently expose 160x120, 1 byte per pixel.

Verification intent (future work):
- Synthesis-only sanity check of new RTL modules.
- Software pattern write into VRAM and verify readback/scanout once wired.
- Confirm byte-enable behavior and address mapping.
