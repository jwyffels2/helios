with Uart0;
with Gnat_Exit;
with Min;
with Interfaces; use Interfaces;
with Image_Store; use Image_Store;
with Camera;
with Comms;

procedure Helios is

    procedure Put_Byte (B : Byte) is
    begin
        Uart0.Put ("[");
        Uart0.Put (Integer'Image (Natural (B)));
        Uart0.Put ("] ");
    end Put_Byte;

    procedure Print_Image_Preview
        (Buf        : Byte_Array;
         Total_Len  : Natural;
         Max_Bytes  : Natural := 96) is
        Preview_Count : Natural := Total_Len;
    begin
        if Preview_Count > Max_Bytes then
            Preview_Count := Max_Bytes;
        end if;

        Uart0.Put ("IMAGE_PREVIEW ");
        for I in 0 .. Preview_Count - 1 loop
            Put_Byte (Buf (I));
        end loop;
        Uart0.Put (ASCII.CR & ASCII.LF);
    end Print_Image_Preview;

    Img_Len : Natural := 0;
    Success : Boolean := False;

begin

    Uart0.Init (19200);

    Uart0.Put ("Boot");
    Uart0.Put (ASCII.CR & ASCII.LF);

    Camera.Init;

    Uart0.Put ("CAMERA_CAPTURE_START");
    Uart0.Put (ASCII.CR & ASCII.LF);

    Camera.Capture_Image (Img_Len, Success);

    if Success then
        Uart0.Put ("CAPTURE_OK");
        Uart0.Put (ASCII.CR & ASCII.LF);

        Uart0.Put ("IMG_LEN=");
        Uart0.Put (Integer'Image (Img_Len));
        Uart0.Put (ASCII.CR & ASCII.LF);

        Print_Image_Preview (Image_Buf, Img_Len, 96);

        Uart0.Put ("COMMS_INIT");
        Uart0.Put (ASCII.CR & ASCII.LF);
        Comms.Init;

        Uart0.Put ("COMMS_SEND_LOOP_START");
        Uart0.Put (ASCII.CR & ASCII.LF);

        -- IMPORTANT: after this, no more UART0 debug prints
        Comms.Send_Image_Loop (Img_Len);

    else
        Uart0.Put ("CAPTURE_FAILED");
        Uart0.Put (ASCII.CR & ASCII.LF);
    end if;

    loop
        null;
    end loop;

end Helios;
