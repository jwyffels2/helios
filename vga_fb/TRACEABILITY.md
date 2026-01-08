@'
# Traceability Notes (VGA Framebuffer / VRAM)

This branch is **not** claiming VGA is solved end-to-end.
Justin has demonstrated VGA output (color bars / signal path), but this work targets a *different slice*:

- A CPU-writable framebuffer (VRAM) path that can drive VGA scanout from memory contents.
- This is also the bridge needed for future work: camera capture -> buffer -> VGA.

Verification intent (future):
- Write test pattern from Ada into VRAM, confirm expected frame output.
- Confirm address map + byte enables (32-bit writes).
- Confirm scanout timing and bandwidth.

Status:
- Scaffold only. Modules compile as stubs and are not integrated into the top-level yet.
'@ | Set-Content -Encoding UTF8 vga_fb\TRACEABILITY.md
