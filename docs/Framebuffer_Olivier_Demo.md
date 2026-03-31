# Framebuffer Demo for Olivier

## Goal

Show that the FPGA now has a working framebuffer path:

1. software writes pixel bytes into a memory-mapped framebuffer
2. the NEORV32 reaches that memory over XBUS
3. the VGA scanout block reads the framebuffer continuously
4. the monitor shows the resulting image

The key point is that this is no longer just timing generation. The CPU can
change memory contents and the display updates from those writes.

## What is in the design

- `rtl/vram_xbus_slave.vhd`
  - maps the framebuffer into the NEORV32 XBUS address space
- `rtl/vram_rgb332_dp.vhd`
  - stores a `160x120` `RGB332` framebuffer in BRAM
- `rtl/vga_scanout_rgb332.vhd`
  - reads framebuffer bytes and drives `640x480` VGA output
- `rtl/helios.vhdl`
  - ties the CPU, XBUS slave, VRAM, and VGA scanout together
- `tests/src/tests.adb`
  - demo app that writes visible test patterns into the framebuffer

## Demo flow

The demo cycles through four patterns:

1. solid black
2. RGBW color bars
3. checkerboard
4. XBUS lane and boundary write pattern

Each pattern holds briefly, clears to black between patterns, and then the full
sequence loops.

## Hardware setup

- use direct `VGA -> VGA`
- do **not** use a passive `VGA -> HDMI` adapter
- Basys3 programmed with the framebuffer bitstream
- UART terminal at `19200 8N1`

## Build the demo software

From repo root:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\build_framebuffer_demo.ps1
```

That produces:

```text
tests\bin\tests.exe
```

## Program the FPGA

From repo root:

```powershell
vivado -mode batch -source rtl/build.tcl
vivado -mode batch -source rtl/program.tcl
```

## Upload and run the demo

1. open the serial terminal at `19200 8N1`
2. reset the board
3. stop autoboot
4. type `u`
5. send `tests\bin\tests.exe`
6. wait for `OK`
7. type `e`

Expected UART output:

```text
Framebuffer test start
Pattern 1: solid black
Pattern 2: RGBW bars
Pattern 3: checkerboard
Pattern 4: XBUS lane and boundary writes
Framebuffer test loop restart
```

Expected monitor output:

1. black screen
2. vertical RGBW bars
3. checkerboard
4. final pattern that shows byte-lane and boundary writes worked


