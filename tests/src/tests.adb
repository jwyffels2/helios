with Ada.Text_IO; use Ada.Text_IO;
with Gnat_Exit;
with Interfaces;  use Interfaces;
with System;
with Uart0;

procedure Tests is

   FB_Base   : constant System.Address := System'To_Address (16#F000_0000#);
   FB_Width  : constant Natural := 160;
   FB_Height : constant Natural := 120;
   FB_Size   : constant Natural := FB_Width * FB_Height;
   Pattern_Hold_Iterations : constant Positive := 100_000_000;
   Inter_Test_Iterations   : constant Positive := 100_000_000;
   Loop_Restart_Iterations : constant Positive := 500_000_000;
   Spin_Accumulator        : Unsigned_32 := 0;
   pragma Volatile (Spin_Accumulator);

   subtype Color_332 is Unsigned_8;
   subtype X_Coord is Natural range 0 .. FB_Width - 1;
   subtype Y_Coord is Natural range 0 .. FB_Height - 1;

   type Framebuffer is array (0 .. FB_Size - 1) of Color_332;
   for Framebuffer'Component_Size use 8;
   pragma Volatile_Components (Framebuffer);

   subtype Half_16 is Unsigned_16;
   subtype Word_32 is Unsigned_32;

   type Framebuffer_Halfs is array (0 .. ((FB_Size + 1) / 2) - 1) of Half_16;
   for Framebuffer_Halfs'Component_Size use 16;
   pragma Volatile_Components (Framebuffer_Halfs);

   type Framebuffer_Words is array (0 .. ((FB_Size + 3) / 4) - 1) of Word_32;
   for Framebuffer_Words'Component_Size use 32;
   pragma Volatile_Components (Framebuffer_Words);

   FB : Framebuffer;
   for FB'Address use FB_Base;
   FB_H : Framebuffer_Halfs;
   for FB_H'Address use FB_Base;
   FB_W : Framebuffer_Words;
   for FB_W'Address use FB_Base;

   function Pixel_Index (X : X_Coord; Y : Y_Coord) return Natural is
   begin
      return (Y * FB_Width) + X;
   end Pixel_Index;

   procedure Put_Pixel (X : X_Coord; Y : Y_Coord; C : Color_332) is
   begin
      FB (Pixel_Index (X, Y)) := C;
   end Put_Pixel;

   procedure Fill (C : Color_332) is
   begin
      for I in FB'Range loop
         FB (I) := C;
      end loop;
   end Fill;

   procedure Draw_Bars is
      Bar_Width : constant Natural := FB_Width / 4;
   begin
      for Y in Y_Coord loop
         for X in X_Coord loop
            if X < Bar_Width then
               Put_Pixel (X, Y, 16#E0#);
            elsif X < (2 * Bar_Width) then
               Put_Pixel (X, Y, 16#1C#);
            elsif X < (3 * Bar_Width) then
               Put_Pixel (X, Y, 16#03#);
            else
               Put_Pixel (X, Y, 16#FF#);
            end if;
         end loop;
      end loop;
   end Draw_Bars;

   procedure Draw_Checkerboard (Cell_Size : Positive) is
   begin
      for Y in Y_Coord loop
         for X in X_Coord loop
            if ((X / Cell_Size) + (Y / Cell_Size)) mod 2 = 0 then
               Put_Pixel (X, Y, 16#00#);
            else
               Put_Pixel (X, Y, 16#FF#);
            end if;
         end loop;
      end loop;
   end Draw_Checkerboard;

   procedure Run_XBus_Write_Test is
      Last_Byte_Idx : constant Natural := FB_Size - 1;
      Last_Half_Idx : constant Natural := Last_Byte_Idx / 2;
      Last_Word_Idx : constant Natural := Last_Byte_Idx / 4;
   begin
      Fill (16#00#);

      FB_W (0) := 16#E0_1C_03_FF#;
      FB_H (2) := 16#FF_E0#;
      FB (6) := 16#1C#;
      FB (7) := 16#03#;

      Put_Pixel (0, 0, 16#E0#);
      Put_Pixel (FB_Width - 1, 0, 16#1C#);
      Put_Pixel (0, FB_Height - 1, 16#03#);
      Put_Pixel (FB_Width - 1, FB_Height - 1, 16#FF#);

      for Y in Y_Coord loop
         Put_Pixel (X_Coord ((Y * 13) mod FB_Width), Y, 16#FF#);
      end loop;

      FB_W (Last_Word_Idx) := 16#03_1C_E0_FF#;
      if Last_Half_Idx in FB_H'Range then
         FB_H (Last_Half_Idx) := 16#E0_FF#;
      end if;
      FB (Last_Byte_Idx) := 16#FF#;
   end Run_XBus_Write_Test;

   procedure Wait_Spin (Iterations : Positive) is
   begin
      for I in 1 .. Iterations loop
         Spin_Accumulator := Spin_Accumulator + 1;
      end loop;
   end Wait_Spin;

   procedure Inter_Test_Blackout is
   begin
      Fill (16#00#);
      Wait_Spin (Inter_Test_Iterations);
   end Inter_Test_Blackout;

   procedure Run_Demo_Pass is
   begin
      Fill (16#00#);
      Put_Line ("Pattern 1: solid black");
      Wait_Spin (Pattern_Hold_Iterations);
      Inter_Test_Blackout;

      Draw_Bars;
      Put_Line ("Pattern 2: RGBW bars");
      Wait_Spin (Pattern_Hold_Iterations);
      Inter_Test_Blackout;

      Draw_Checkerboard (8);
      Put_Line ("Pattern 3: checkerboard");
      Wait_Spin (Pattern_Hold_Iterations);
      Inter_Test_Blackout;

      Run_XBus_Write_Test;
      Put_Line ("Pattern 4: XBUS lane and boundary writes");
      Wait_Spin (Pattern_Hold_Iterations);
      Inter_Test_Blackout;
   end Run_Demo_Pass;

begin
   -- Keep the demo UART aligned with the default bootloader terminal setup.
   Uart0.Init (19200);
   Put_Line ("Framebuffer test start");
   loop
      Run_Demo_Pass;
      Put_Line ("Framebuffer test loop restart");
      Wait_Spin (Loop_Restart_Iterations);
   end loop;
end Tests;
