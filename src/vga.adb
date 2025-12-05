with Interfaces; use Interfaces;

package body VGA is

   ------------------------------------------------------------------
   -- Control API
   ------------------------------------------------------------------
   procedure Enable is
   begin
      -- Set bit 0 of CTRL
      VGA_HW.CTRL := VGA_HW.CTRL or 1;
   end Enable;

   procedure Disable is
   begin
      -- Clear bit 0 of CTRL
      VGA_HW.CTRL := VGA_HW.CTRL and not 1;
   end Disable;

   procedure Set_Background (R, G, B : Unsigned_8) is
      Val : Unsigned_32;
   begin
      Val :=
        Unsigned_32 (R and 16#0F#) or
        Shift_Left (Unsigned_32 (G and 16#0F#), 4) or
        Shift_Left (Unsigned_32 (B and 16#0F#), 8);
      VGA_HW.BGCOLOR := Val;
   end Set_Background;

   ------------------------------------------------------------------
   -- Framebuffer API
   ------------------------------------------------------------------

   procedure Put_Pixel (X, Y : Natural; Color : Unsigned_8) is
      Index : Natural := Y * FB_Width + X;
   begin
      if (X < FB_Width) and then (Y < FB_Height) then
         VRAM (Index) := Color;
      end if;
   end Put_Pixel;

   procedure Clear (Color : Unsigned_8) is
   begin
      for I in VRAM'Range loop
         VRAM (I) := Color;
      end loop;
   end Clear;

end VGA;
