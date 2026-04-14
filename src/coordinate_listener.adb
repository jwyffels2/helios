with Ada.Unchecked_Conversion;
with Uart0; use Uart0;
with neorv32; use neorv32;
with neorv32.UART0; use neorv32.UART0;
with Logger;

package body Coordinate_Listener is

   type State_Type is (
      Wait_Start,
      Read_Cmd,
      Read_Len,
      Read_Payload,
      Read_CRC
   );

   State : State_Type := Wait_Start;

   Start_Byte : constant Character := Character'Val (16#AA#);

   Cmd   : Character;
   Len   : Natural := 0;
   Index : Natural := 0;

   Payload : array (0 .. 31) of Character;

   CRC_Calc : Natural := 0;

   type Float_Bytes is array (0 .. 3) of Character;

   function To_Float is new Ada.Unchecked_Conversion
     (Float_Bytes, Float);

   procedure Execute is
      Lat_Bytes : Float_Bytes;
      Lon_Bytes : Float_Bytes;
      Lat : Float;
      Lon : Float;
   begin
      if Cmd = Character'Val (16#01#) then

         for I in 0 .. 3 loop
            Lat_Bytes (I) := Payload (I);
            Lon_Bytes (I) := Payload (I + 4);
         end loop;

         Lat := To_Float (Lat_Bytes);
         Lon := To_Float (Lon_Bytes);

         Logger.Info ("COORDINATES RECEIVED!");
         Logger.Info (Lat'Image);
         Logger.Info (Lon'Image);

         --  THIS IS WHERE CAMERA TRIGGER WILL GO

      end if;
   end Execute;

   procedure Init is
   begin
      State := Wait_Start;
   end Init;

   procedure Poll is
      B : Character;
   begin
      if UART0_Periph.CTRL.UART_CTRL_RX_NEMPTY = 0 then
         return;
      end if;

      B := Read_RX;

      case State is

         when Wait_Start =>
            if B = Start_Byte then
               CRC_Calc := Character'Pos (B);
               State := Read_Cmd;
            end if;

         when Read_Cmd =>
            Cmd := B;
            CRC_Calc := CRC_Calc + Character'Pos (B);
            State := Read_Len;

         when Read_Len =>
            Len := Character'Pos (B);
            Index := 0;
            CRC_Calc := CRC_Calc + Len;
            State := Read_Payload;

         when Read_Payload =>
            Payload (Index) := B;
            CRC_Calc := CRC_Calc + Character'Pos (B);

            Index := Index + 1;

            if Index = Len then
               State := Read_CRC;
            end if;

         when Read_CRC =>
            if (CRC_Calc mod 256) = Character'Pos (B) then
               Execute;
            else
               Logger.Error ("CRC error during coordinate read");
            end if;

            State := Wait_Start;

      end case;
   end Poll;

end Coordinate_Listener;
