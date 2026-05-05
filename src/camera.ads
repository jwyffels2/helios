-- Title: camera.ads
-- Purpose: Public interface for the TTL serial camera driver. Defines the camera byte type and exposes procedures for initializing the camera and capturing image data.
-- Date Modified: 20260505

with Interfaces; use Interfaces;

package Camera is

    subtype Byte is Unsigned_8;

    -- Name: Init
    -- Purpose: Initializes the UART connection used by the camera and clears any pending camera receive data.
    procedure Init;

    -- Name: Capture_Image
    -- Purpose: Captures one image from the camera, stores the image bytes in the shared image buffer, and reports the image length and capture status.
    -- Outputs:
    -- Img_Len : Natural : Number of image bytes captured from the camera.
    -- Success : Boolean : Indicates whether the image capture completed successfully.
    procedure Capture_Image (Img_Len : out Natural; Success : out Boolean);

end Camera;
