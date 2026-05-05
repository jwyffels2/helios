-- This is the min protocol "implementation file" and implements procedures/functions defined in min.ads
-- This one is a bit different though since it imports C functions to use in Ada.
with Interfaces.C;

-- Imported C functions found in min_glue.c
package body Min is

    -- Define C_Init as an imported C function. The C function is named min_glue_init
    procedure C_Init with Import, Convention => C, External_Name => "min_glue_init";

    -- Tiny Ada wrapper for C_Init
    procedure Init is
    begin
        C_Init;
    end Init;

    procedure Min_Glue_Send_Image_Once (Img_Len : Natural) with Import, Convention => C, External_Name => "min_glue_send_image_once";

    procedure Send_Image_Once (Img_Len : Natural) is
    begin
        Min_Glue_Send_Image_Once (Img_Len);
    end Send_Image_Once;

end Min;
