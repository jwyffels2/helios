package body VGA_FB is

   -- This array overlays the framebuffer MMIO region directly. Each element is
   -- one byte so software indexing matches the RGB332 storage layout exactly.
   type Framebuffer is array (0 .. FB_SIZE - 1) of Color_332;
   for Framebuffer'Component_Size use 8;

   FB : Framebuffer;

   -- Volatile_Components prevents the compiler from optimizing away writes to
   -- the memory-mapped region. Every assignment must become a real store.
   pragma Volatile_Components (FB);
   for FB'Address use FB_BASE;

   procedure Put_Pixel (X : X_Coord; Y : Y_Coord; C : Color_332) is
      -- Row-major byte offset into the framebuffer window.
      Idx : constant Natural := (Y * FB_WIDTH) + X;
   begin
      FB (Idx) := C;
   end Put_Pixel;

   procedure Fill (C : Color_332) is
   begin
      -- Walk the full MMIO window in order so the hardware sees a simple stream
      -- of byte writes. This is convenient for bring-up and pattern tests.
      for I in FB'Range loop
         FB (I) := C;
      end loop;
   end Fill;

end VGA_FB;
