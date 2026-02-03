with System;
with Interfaces;

package VGA_FB is
   -- Software contract: must match the RTL decode window (vram_wb_slave BASE_ADDR).
   -- This is in the NEORV32 XBUS/uncached address region.
   FB_BASE : constant System.Address := System'To_Address (16#F0000000#);

   -- Initial format/resolution assumptions (match vga_fb_pkg.vhd)
   FB_W : constant Natural := 160;
   FB_H : constant Natural := 120;
   FB_SIZE_BYTES : constant Natural := FB_W * FB_H;

   -- Minimal API (stubs are fine for now, but compiles + shows intent)
   procedure Put_Pixel (X, Y : Natural; Color : Interfaces.Unsigned_8);
   procedure Fill (Color : Interfaces.Unsigned_8);
end VGA_FB;
