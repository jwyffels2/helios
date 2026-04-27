with Uart0;
with Gnat_Exit;
with PWM_API; use PWM_API;
with Image_Store; use Image_Store;
with Camera;
with Comms;
with VGA_FB;

procedure Helios is

   Pwm0 : PWM_T := Create (Channel => 0);

   procedure Put_Byte (B : Byte) is
   begin
      Uart0.Put ("[");
      Uart0.Put (Integer'Image (Natural (B)));
      Uart0.Put ("] ");
   end Put_Byte;

   procedure Print_Image_Preview
      (Buf       : Byte_Array;
       Total_Len : Natural;
       Max_Bytes : Natural := 96)
   is
      Preview_Count : Natural := Total_Len;
   begin
      if Preview_Count > Max_Bytes then
         Preview_Count := Max_Bytes;
      end if;

      Uart0.Put ("IMAGE_PREVIEW ");
      if Preview_Count > 0 then
         for I in 0 .. Preview_Count - 1 loop
            Put_Byte (Buf (I));
         end loop;
      end if;
      Uart0.Put (ASCII.CR & ASCII.LF);
   end Print_Image_Preview;

   procedure Draw_Framebuffer_Test_Pattern is
      use VGA_FB;

      -- RGB332 packs one pixel into one byte:
      -- bits 7..5 = red, bits 4..2 = green, bits 1..0 = blue.
      -- These visible bars make it obvious that CPU writes are reaching VRAM.
      Red   : constant Color_332 := 16#E0#;
      Green : constant Color_332 := 16#1C#;
      Blue  : constant Color_332 := 16#03#;
      White : constant Color_332 := 16#FF#;
      Pixel : Color_332;
   begin
      for Y in Y_Coord loop
         for X in X_Coord loop
            if X < FB_WIDTH / 3 then
               Pixel := Red;
            elsif X < (2 * FB_WIDTH) / 3 then
               Pixel := Green;
            else
               Pixel := Blue;
            end if;

            -- Draw a thin white diagonal over the color bars. If this line is
            -- misplaced, the issue is usually address math rather than color.
            if X = (Y * FB_WIDTH) / FB_HEIGHT then
               Pixel := White;
            end if;

            Put_Pixel (X, Y, Pixel);
         end loop;
      end loop;
   end Draw_Framebuffer_Test_Pattern;

   procedure Do_Initialize is
   begin
      Uart0.Put ("INIT_START");
      Uart0.Put (ASCII.CR & ASCII.LF);

      Camera.Init;
      Comms.Init;
      Draw_Framebuffer_Test_Pattern;

      Uart0.Put ("INIT_OK");
      Uart0.Put (ASCII.CR & ASCII.LF);
   end Do_Initialize;

   procedure Do_Capture is
      Img_Len : Natural := 0;
      Success : Boolean := False;
   begin
      Uart0.Put ("CAPTURE_START");
      Uart0.Put (ASCII.CR & ASCII.LF);

      Camera.Capture_Image (Img_Len, Success);

      if Success then
         Uart0.Put ("CAPTURE_OK");
         Uart0.Put (ASCII.CR & ASCII.LF);

         Uart0.Put ("IMG_LEN=");
         Uart0.Put (Integer'Image (Img_Len));
         Uart0.Put (ASCII.CR & ASCII.LF);

         Print_Image_Preview (Image_Buf, Img_Len, 96);

         Uart0.Put ("SEND_START");
         Uart0.Put (ASCII.CR & ASCII.LF);

         -- Send one image burst per command so a failed transfer is visible and
         -- recoverable at the command level instead of hiding in an endless loop.
         Comms.Send_Image (Img_Len);

         Uart0.Put ("SEND_DONE");
         Uart0.Put (ASCII.CR & ASCII.LF);
      else
         Uart0.Put ("CAPTURE_FAILED");
         Uart0.Put (ASCII.CR & ASCII.LF);
      end if;
   end Do_Capture;

   Cmd : Character;

begin
   -- Keep the application UART rate aligned with the terminal setup used for
   -- the bootloader workflow on the Basys3.
   Uart0.Init (19200);

   -- Channel 0 is pinned out in the XDC. Keep it enabled so board-level tests
   -- can confirm the PWM path still works after the framebuffer merge.
   Pwm0.Configure (Target_Hz => 5.0, Duty => 0.5);
   Pwm0.Enable;

   -- Paint the framebuffer once at boot so VGA bring-up does not depend on a
   -- serial command being sent first.
   Draw_Framebuffer_Test_Pattern;

   Uart0.Put ("BOOT_OK");
   Uart0.Put (ASCII.CR & ASCII.LF);
   Uart0.Put ("WAITING_FOR_COMMANDS");
   Uart0.Put (ASCII.CR & ASCII.LF);

   loop
      Cmd := Uart0.Read_RX;

      case Cmd is
         when 'i' | 'I' =>
            Do_Initialize;

         when 'c' | 'C' =>
            Do_Capture;

         when 'f' | 'F' =>
            Draw_Framebuffer_Test_Pattern;
            Uart0.Put ("FRAMEBUFFER_PATTERN_OK");
            Uart0.Put (ASCII.CR & ASCII.LF);

         when others =>
            Uart0.Put ("UNKNOWN_COMMAND");
            Uart0.Put (ASCII.CR & ASCII.LF);
      end case;
   end loop;

end Helios;
