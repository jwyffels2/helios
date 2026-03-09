-- This is the min protocol "implementation file" and implements procedures/functions defined in min.ads
-- This one is a bit different though since it imports C functions to use in Ada.
with Interfaces.C;

-- Imported C functions found in min_glue.c
package body Min is

    -- Define C_Init as an imported C function. The C function is named min_glue_init
    procedure C_Init with Import, Convention => C, External_Name => "min_glue_init";
    -- Define C_Send_Test as an imported C function. The C function is named min_glue_send_test
    procedure C_Send_Test with Import, Convention => C, External_Name => "min_glue_send_test";

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

end Min;
