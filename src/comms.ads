package Comms is

    -- Starts communication system
    procedure Init;

    -- Sends the stored image repeatedly using the length provided by the caller
    procedure Send_Image_Loop (Img_Len : Natural);

end Comms;
