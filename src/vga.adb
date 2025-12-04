with Interfaces; use Interfaces;

package body VGA is

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
      -- Only use low 4 bits of each channel
      Val :=
        Unsigned_32 (R and 16#0F#) or
        Shift_Left (Unsigned_32 (G and 16#0F#), 4) or
        Shift_Left (Unsigned_32 (B and 16#0F#), 8);

      VGA_HW.BGCOLOR := Val;
   end Set_Background;

end VGA;
