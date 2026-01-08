with Interfaces;

package VGA_FB is
   -- Step 1 software contract: same base address as VHDL.
   FB_BASE : constant Interfaces.Unsigned_32 := 16#F000_0000#;

   -- Initial format/resolution assumptions (match vga_fb_pkg.vhd)
   FB_W : constant := 160;
   FB_H : constant := 120;

   -- Minimal API (stubs are fine for now, but compiles + shows intent)
   procedure Put_Pixel (X, Y : Natural; Color : Interfaces.Unsigned_8);
   procedure Fill (Color : Interfaces.Unsigned_8);
end VGA_FB;
