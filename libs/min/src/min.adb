-- This is the min protocol "implementation file" and implements procedures/functions defined in min.ads
-- This one is a bit different though since it imports C functions to use in Ada.
with Interfaces.C;

-- Imported C functions found in min_glue.c
package body Min is

    -- Define C_Init as an imported C function. The C function is named min_glue_init
    procedure C_Init with Import, Convention => C, External_Name => "min_glue_init";
    -- Define C_Send_Test as an imported C function. The C function is named min_glue_send_test
    procedure C_Send_Test with Import, Convention => C, External_Name => "min_glue_send_test";

    procedure C_Send_Image_Loop (Length : Interfaces.C.unsigned) with Import, Convention => C, External_Name => "min_glue_send_image_loop";

    -- Tiny Ada wrapper for C_Init
    procedure Init is
    begin
        C_Init;
    end Init;

    -- Tiny Ada wrapper for Send_Test
    procedure Send_Test is
    begin
        C_Send_Test;
    end Send_Test;

    -- A loop to send the image multiple times
    procedure Send_Image_Loop (Length : Natural) is
    begin
        C_Send_Image_Loop (Interfaces.C.unsigned (Length));
    end Send_Image_Loop;

    procedure Min_Glue_Send_Image_Once (Img_Len : Natural) with Import, Convention => C, External_Name => "min_glue_send_image_once";

    procedure Send_Image_Once (Img_Len : Natural) is
    begin
        Min_Glue_Send_Image_Once (Img_Len);
    end Send_Image_Once;

end Min;
