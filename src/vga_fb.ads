with Interfaces;
with System;

package VGA_FB is

   -- Software view of the framebuffer MMIO window implemented in RTL.
   -- The base address must match the XBUS slave instantiated in rtl/helios.vhdl.
   FB_BASE   : constant System.Address := System'To_Address (16#F000_0000#);

   -- Frame dimensions are fixed in hardware for now. Keep these constants in
   -- sync with the BRAM sizing used by the framebuffer RTL.
   FB_WIDTH  : constant Natural := 160;
   FB_HEIGHT : constant Natural := 120;
   FB_SIZE   : constant Natural := FB_WIDTH * FB_HEIGHT;

   subtype X_Coord is Natural range 0 .. FB_WIDTH  - 1;
   subtype Y_Coord is Natural range 0 .. FB_HEIGHT - 1;

   subtype Color_332 is Interfaces.Unsigned_8;

   -- Store one RGB332 pixel at (X, Y).
   procedure Put_Pixel (X : X_Coord; Y : Y_Coord; C : Color_332);

   -- Fill the whole framebuffer with one RGB332 color byte. This is useful for
   -- visible VGA smoke tests because it exercises a large number of sequential
   -- MMIO writes and produces a full-screen color pattern.
   procedure Fill (C : Color_332);

end VGA_FB;

