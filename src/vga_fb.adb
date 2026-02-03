with System;
with Interfaces;

package body VGA_FB is
   use Interfaces;

   -- Treat framebuffer as a byte-addressable MMIO window.
   -- Using Volatile helps keep writes from being optimized out.
   type Byte_Array is array (Natural range <>) of Unsigned_8
     with Pack;

   -- Map the framebuffer region; RTL decodes a larger window, but only
   -- FB_W * FB_H bytes are used for pixels.

   FB : Byte_Array (0 .. FB_SIZE_BYTES - 1)
     with Import, Volatile,
          Address => FB_BASE;

   -- Word view for faster clears/fills. This is safe because the framebuffer
   -- size is a multiple of 4 for the current 160x120@RGB332 setup.
   type Word_Array is array (Natural range <>) of Unsigned_32;
   FB32 : Word_Array (0 .. (FB_SIZE_BYTES / 4) - 1)
     with Import, Volatile,
          Address => FB_BASE;

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
      C32     : constant Unsigned_32 := Unsigned_32 (Color);
      Pattern : constant Unsigned_32 :=
        C32 or Shift_Left (C32, 8) or Shift_Left (C32, 16) or Shift_Left (C32, 24);
      Tail_Start : constant Natural := (FB_SIZE_BYTES / 4) * 4;
   begin
      -- Use 32-bit writes for throughput; RTL expands/strobes byte enables.
      for I in FB32'Range loop
         FB32 (I) := Pattern;
      end loop;

      -- Tail bytes (in case FB_SIZE_BYTES is not a multiple of 4).
      for I in Tail_Start .. FB'Last loop
         FB (I) := Color;
      end loop;
   end Fill;

end VGA_FB;
