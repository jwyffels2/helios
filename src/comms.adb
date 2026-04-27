with Min;

package body Comms is

    procedure Init is
    begin
        Min.Init;
    end Init;

    procedure Send_Image_Loop (Img_Len : Natural) is
    begin
        Min.Send_Image_Loop (Img_Len);
    end Send_Image_Loop;

    procedure Send_Image (Img_Len : Natural) is
    begin
        -- Send one image burst (no loop)
        Min.Send_Image_Once (Img_Len);
    end Send_Image;

end Comms;
