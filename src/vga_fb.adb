with System;
with Interfaces;

package body VGA_FB is
   use Interfaces;

   -- Treat framebuffer as a byte-addressable MMIO window.
   -- Using Volatile helps keep writes from being optimized out.
   type Byte_Array is array (Natural range <>) of Unsigned_8
     with Pack;

   -- Map a 64 KiB window (must match VGA_FB_SIZE in VHDL package).
   FB_SIZE_BYTES : constant := 64 * 1024;

   FB : Byte_Array (0 .. FB_SIZE_BYTES - 1)
     with Import, Volatile,
          Address => System'To_Address (Integer_Address (FB_BASE));

   function Idx (X, Y : Natural) return Natural is
   begin
      -- 1 byte per pixel placeholder
      return (Y * FB_W) + X;
   end Idx;

   procedure Put_Pixel (X, Y : Natural; Color : Unsigned_8) is
      I : constant Natural := Idx (X, Y);
   begin
      if X < FB_W and Y < FB_H and I < FB_SIZE_BYTES then
         FB (I) := Color;
      end if;
   end Put_Pixel;

   procedure Fill (Color : Unsigned_8) is
   begin
      for I in FB'Range loop
         FB (I) := Color;
      end loop;
   end Fill;

end VGA_FB;
