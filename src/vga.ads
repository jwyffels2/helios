with System;
with Interfaces; use Interfaces;

package VGA is

   -- Base address of VGA xBUS peripheral
   VGA_Base : constant System.Address := System.Address (16#8000_0000#);

   -- Memory-mapped register layout
   type VGA_Registers is record
      CTRL    : Unsigned_32;  -- offset 0x00
      BGCOLOR : Unsigned_32;  -- offset 0x04
   end record;

   pragma Volatile (VGA_Registers);
   for VGA_Registers'Size use 64;  -- two 32-bit registers

   -- The actual hardware instance
   VGA_HW : aliased VGA_Registers;
   for VGA_HW'Address use VGA_Base;

   -- High-level helper API
   procedure Enable;
   procedure Disable;

   -- Set solid background color (4-bit per channel: 0..15)
   procedure Set_Background (R, G, B : Unsigned_8);

end VGA;
