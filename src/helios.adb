-- Title: helios.adb
-- Purpose: Main control program for the CubeSat camera and communication system.
-- Initializes board communication, listens for ground-station commands, captures images, previews image bytes, and sends image data through the communication driver.
-- Date Modified: 20260505

with Uart0;
with Gnat_Exit;
with Min;
with Interfaces; use Interfaces;
with Image_Store; use Image_Store;
with Camera;
with Comms;
with Logger;
with Coordinate_Listener;

procedure Helios is

    -- Name: Put_Byte
    -- Purpose: Prints one image byte to UART0 for debugging and image preview
    -- Inputs:
    -- B : Byte : Byte value from the image buffer to print
    procedure Put_Byte (B : Byte) is
    begin
        Uart0.Put ("[");
        Uart0.Put (Integer'Image (Natural (B)));
        Uart0.Put ("] ");
    end Put_Byte;

    -- Name: Print_Image_Preview
    -- Purpose: Prints the first bytes of the captured image buffer to UART0 for debugging and JPEG verification.
    -- Inputs:
    -- Buf : Byte_Array : Image buffer containing the captured image data.
    -- Total_Len : Natural : Total number of bytes captured in the image buffer.
    -- Max_Bytes : Natural : Maximum number of image bytes to print in the preview.
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

    -- Name: Do_Initialize
    -- Purpose: Initializes the camera driver and communication driver after receiving an initialize command from the ground station.
    procedure Do_Initialize is
    begin
        --Uart0.Put ("INIT_START");
        Uart0.Put (ASCII.CR & ASCII.LF);

        Camera.Init;
        Comms.Init;

        --Uart0.Put ("INIT_OK");
        Uart0.Put (ASCII.CR & ASCII.LF);
    end Do_Initialize;

    -- Name: Do_Capture
    -- Purpose: Captures an image from the camera, prints capture status information, previews the image data, and sends the image through the communication driver.
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

            -- For now send one image burst, not an infinite loop
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
    -- Init UART0 for communication with board
    Uart0.Init (19200);
    -- Boot confirmation
    Uart0.Put ("BOOT_OK");
    Uart0.Put (ASCII.CR & ASCII.LF);

    -- Initialize coordinate listener
    Coordinate_Listener.Init;
    Uart0.Put ("BOOT_OK - COORD LISTENER");
    Uart0.Put (ASCII.CR & ASCII.LF);

    -- Listen for commands message
    Uart0.Put ("WAITING_FOR_COMMANDS");
    Uart0.Put (ASCII.CR & ASCII.LF);

    -- Main listener loop
    -- Listens for commands from GUI and/or keyboard input while TerraTerm is open
    loop
        Cmd := Uart0.Read_RX;

        case Cmd is
            when 'i' | 'I' =>
                Do_Initialize;

            when 'c' | 'C' =>
                Do_Capture;

            when others =>
                null;
        end case;

    end loop;

end Helios;
