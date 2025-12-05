with System;
with System.Storage_Elements;
with Interfaces; use Interfaces;

package VGA is

   use System.Storage_Elements;

   ------------------------------------------------------------------
   -- Register block (XBUS @ 0x4000_0000)
   ------------------------------------------------------------------
   -- Base address in the "void" region => goes to XBUS
   VGA_Base : constant System.Address := To_Address (16#4000_0000#);

   type VGA_Registers is record
      CTRL    : Unsigned_32;  -- offset 0x00
      BGCOLOR : Unsigned_32;  -- offset 0x04
   end record;

   pragma Volatile (VGA_Registers);
   for VGA_Registers'Size use 64;

   VGA_HW : aliased VGA_Registers;
   for VGA_HW'Address use VGA_Base;

   ------------------------------------------------------------------
   -- Framebuffer: 320x240 @ 8bpp, mapped at 0x4000_1000
   -- Must match the VHDL:
   --   - VRAM region decode (xbus_adr_i(15..12) = "0001")
   --   - FB_WIDTH/FB_HEIGHT/BPP generics
   ------------------------------------------------------------------
   VGA_VRAM_Base : constant System.Address := To_Address (16#4000_1000#);

   FB_Width  : constant := 320;
   FB_Height : constant := 240;
   FB_Size   : constant := FB_Width * FB_Height;  -- 76_800 bytes

   type Framebuffer_Array is array (0 .. FB_Size - 1) of Unsigned_8;
   pragma Volatile (Framebuffer_Array);
   for Framebuffer_Array'Component_Size use 8;

   VRAM : aliased Framebuffer_Array;
   for VRAM'Address use VGA_VRAM_Base;

   ------------------------------------------------------------------
   -- Control API
   ------------------------------------------------------------------
   procedure Enable;
   procedure Disable;
   procedure Set_Background (R, G, B : Unsigned_8);

   ------------------------------------------------------------------
   -- Framebuffer API
   ------------------------------------------------------------------
   procedure Put_Pixel (X, Y : Natural; Color : Unsigned_8);
   procedure Clear (Color : Unsigned_8);

end VGA;
