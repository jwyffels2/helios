with Interfaces; use Interfaces;

package Image_Store is

    subtype Byte is Unsigned_8;
    type Byte_Array is array (Natural range <>) of Byte;

    Max_Image_Size : constant Natural := 60_000;

    Image_Buf : Byte_Array (0 .. Max_Image_Size - 1);
    pragma Export (C, Image_Buf, "image_buf");

end Image_Store;
