Helios framebuffer end project README
-------------------------------------

GitHub repository:
https://github.com/jwyffels2/helios

This branch adds the framebuffer path needed for the end project. The goal is
to let Ada software draw pixels into memory and have the FPGA display those
pixels on a VGA monitor.


What this branch includes
-------------------------

The branch includes only the runtime framebuffer pieces needed by the final
project:

  src/vga_fb.ads
    Ada package spec for framebuffer constants and drawing procedures.

  src/vga_fb.adb
    Ada package body that maps the framebuffer into memory and writes pixels.

  src/helios.adb
    Main program hook that draws a visible test pattern on boot and on the
    f or F UART command.

  rtl/helios.vhdl
    Basys3 top level that connects NEORV32, the framebuffer bus slave, VRAM,
    and VGA scanout.

  rtl/vram_xbus_slave.vhd
    NEORV32 XBUS slave for the framebuffer memory window.

  rtl/vram_rgb332_dp.vhd
    Dual-port framebuffer memory.

  rtl/vga_scanout_rgb332.vhd
    VGA scanout block that reads framebuffer pixels and drives VGA color and
    sync signals.

  rtl/vga_640x480_timing.vhd
    Standard 640 by 480 VGA timing generator.

  rtl/basys3_a7_test_setup.xdc
    Basys3 pin constraints, including VGA pins.

  rtl/build.tcl
    Vivado build script that adds the framebuffer RTL to the bitstream.

  build_neorv32_project.sh
    Software build helper for creating a NEORV32 bootloader image.


How the framebuffer works
-------------------------

The software writes one byte per pixel into the framebuffer memory window at
address 0xF000_0000. NEORV32 sends those writes over XBUS. The RTL bus slave
accepts writes in that address range and forwards them to the framebuffer BRAM.
The VGA scanout logic reads that BRAM continuously and drives the monitor.

Data path:

  Ada code in src/vga_fb.adb
    to NEORV32 XBUS
    to rtl/vram_xbus_slave.vhd
    to rtl/vram_rgb332_dp.vhd
    to rtl/vga_scanout_rgb332.vhd
    to Basys3 VGA output pins

The framebuffer stores a 160 by 120 image. The VGA output is 640 by 480, so
each framebuffer pixel is shown as a 4 by 4 block on the monitor.

Each pixel is one RGB332 byte:

  bits 7 through 5 hold red
  bits 4 through 2 hold green
  bits 1 through 0 hold blue

Useful colors:

  0xE0 for red
  0x1C for green
  0x03 for blue
  0xFF for white
  0x00 for black

The framebuffer is currently write-only from software. Hardware acknowledges
software reads from the framebuffer window, but read data is zero. Use writes
only unless a future branch adds a real read path.


How to use the framebuffer from Ada
-----------------------------------

Use the VGA_FB package from src/vga_fb.ads and src/vga_fb.adb.

Basic example:

  with VGA_FB;

  procedure Draw_Corners is
     use VGA_FB;
  begin
     Fill (16#00#);

     Put_Pixel (0, 0, 16#E0#);
     Put_Pixel (FB_WIDTH - 1, 0, 16#1C#);
     Put_Pixel (0, FB_HEIGHT - 1, 16#03#);
     Put_Pixel (FB_WIDTH - 1, FB_HEIGHT - 1, 16#FF#);
  end Draw_Corners;

Draw vertical color bars:

  with VGA_FB;

  procedure Draw_Bars is
     use VGA_FB;
  begin
     for Y in Y_Coord loop
        for X in X_Coord loop
           if X < FB_WIDTH / 4 then
              Put_Pixel (X, Y, 16#E0#);
           elsif X < FB_WIDTH / 2 then
              Put_Pixel (X, Y, 16#1C#);
           elsif X < (3 * FB_WIDTH) / 4 then
              Put_Pixel (X, Y, 16#03#);
           else
              Put_Pixel (X, Y, 16#FF#);
           end if;
        end loop;
     end loop;
  end Draw_Bars;

Important usage notes:

  Use X_Coord and Y_Coord for pixel positions. X ranges from 0 through 159.
  Y ranges from 0 through 119.

  Use Color_332 values. The framebuffer stores one byte per pixel, not full
  24-bit color.

  Use Fill to clear or repaint the whole framebuffer.

  Keep the framebuffer base address and dimensions synchronized between Ada
  and RTL if they are changed later.


Main application behavior
-------------------------

src/helios.adb draws a framebuffer test pattern when the program boots. The
pattern is red, green, and blue bars with a white diagonal line. This gives an
immediate visual check that:

  CPU writes reach framebuffer memory,
  RGB color expansion works,
  row and column address math is correct.

The main UART command loop also accepts f or F. That command redraws the
framebuffer pattern and prints:

  FRAMEBUFFER_PATTERN_OK


Build and program
-----------------

Initialize submodules:

  git submodule update --init --recursive

Build the Ada application into a NEORV32 bootloader image:

  podman machine start
  podman run --rm -v "${PWD}:/workspace" -w /workspace localhost/helios-build:latest bash -lc "./build_neorv32_project.sh ./bin/helios"

Build the Basys3 bitstream:

  vivado -mode batch -source rtl/build.tcl

Program the Basys3:

  vivado -mode batch -source rtl/program.tcl


Hardware setup
--------------

Use:

  Basys3 board
  direct VGA to VGA cable
  UART terminal at 19200 8N1

Do not use a passive VGA to HDMI adapter. VGA is analog and HDMI is digital, so
a passive adapter usually will not display anything.


Design assumptions
------------------

The stored framebuffer resolution is 160 by 120.

The displayed VGA resolution is 640 by 480.

Framebuffer pixels use RGB332 in memory and are expanded to the Basys3 VGA
channel width by the scanout block.

NEORV32 and VGA scanout share the 100 MHz Basys3 clock in this branch.

The framebuffer software interface is write-only for now.


Future extension points
-----------------------

Good next steps for future students:

  Add drawing helpers to src/vga_fb.ads and src/vga_fb.adb, such as lines,
  rectangles, sprites, or text.

  Replace the boot test pattern in src/helios.adb with mission data or camera
  output once those features are ready.

  Add a real framebuffer read path only if software needs to inspect pixels.
  That will require RTL changes in vram_xbus_slave and careful handling of
  memory reads while VGA scanout is active.


Troubleshooting
---------------

No image:

  Rebuild and reprogram the bitstream.
  Confirm reset is released.
  Use a direct VGA monitor or active converter.
  Confirm the Ada program was uploaded and started.

Wrong colors:

  Check the RGB332 color byte values.
  Check rtl/vga_scanout_rgb332.vhd.
  Check VGA pin mappings in rtl/basys3_a7_test_setup.xdc.

Image shifted or corrupted:

  Check row and column address math in the Ada code.
  Confirm framebuffer dimensions match between Ada and RTL.

CPU appears to write but display does not change:

  Confirm writes target address 0xF000_0000.
  Check rtl/vram_xbus_slave.vhd.
  Check rtl/vram_rgb332_dp.vhd.
