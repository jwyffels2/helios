@'
# VGA Framebuffer / VRAM Integration (Scaffold)

Status: **Scaffold only** (no functional implementation yet).

Goal:
- Define a clean interface for a framebuffer-backed VGA pipeline.
- Provide a NEORV32-facing path to write pixels (or test patterns) into VRAM.
- Later: allow camera capture → framebuffer → VGA output (traceability to future camera work).

What exists now:
- VHDL stubs for a framebuffer interface and a simple BRAM-based VRAM placeholder.
- Ada driver stubs that define the intended API surface.
- Notes/TODOs describing integration points (external bus / memory-mapped IO).

What is NOT done yet:
- No external bus wiring.
- No verified timing closure for video scanout.
- No validated address map.
- No integration into the top-level build or constraints.
'@ | Set-Content -Encoding UTF8 vga_fb\README.md