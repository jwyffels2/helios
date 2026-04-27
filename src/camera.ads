with Interfaces; use Interfaces;

package Camera is

    subtype Byte is Unsigned_8;

    -- Sets up camera needs
    procedure Init;

    -- Captures an image
    -- Returns the image length and if the capture was successful
    procedure Capture_Image (Img_Len : out Natural; Success : out Boolean);

end Camera;
