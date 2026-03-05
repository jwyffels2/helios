package body VGA_FB is

   type Framebuffer is array (0 .. FB_SIZE - 1) of Color_332;
   for Framebuffer'Component_Size use 8;

   FB : Framebuffer;
   pragma Volatile_Components (FB);
   for FB'Address use FB_BASE;

   procedure Put_Pixel (X : X_Coord; Y : Y_Coord; C : Color_332) is
      Idx : constant Natural := (Y * FB_WIDTH) + X;
   begin
      FB (Idx) := C;
   end Put_Pixel;

   procedure Fill (C : Color_332) is
   begin
      for I in FB'Range loop
         FB (I) := C;
      end loop;
   end Fill;

end VGA_FB;
