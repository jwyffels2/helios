with Interfaces;
with System;

package VGA_FB is

   -- Memory-mapped framebuffer window (NEORV32 XBUS slave in rtl/helios.vhdl).
   FB_BASE   : constant System.Address := System'To_Address (16#F000_0000#);

   FB_WIDTH  : constant Natural := 160;
   FB_HEIGHT : constant Natural := 120;
   FB_SIZE   : constant Natural := FB_WIDTH * FB_HEIGHT;

   subtype X_Coord is Natural range 0 .. FB_WIDTH  - 1;
   subtype Y_Coord is Natural range 0 .. FB_HEIGHT - 1;

   subtype Color_332 is Interfaces.Unsigned_8;

   procedure Put_Pixel (X : X_Coord; Y : Y_Coord; C : Color_332);
   procedure Fill (C : Color_332);

end VGA_FB;

