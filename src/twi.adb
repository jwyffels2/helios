with Ada.Text_IO;
with neorv32.SYSINFO; use neorv32.SYSINFO;

package body TWI is

   function TWI_Available return Boolean is
   begin
      return SYSINFO_Periph.SOC.SYSINFO_SOC_IO_TWI = 1;
   end TWI_Available;

   procedure TWI_Setup (preScaler : Natural; clockDiv : Natural; allowClockStretching : Boolean) is
      Ctrl : UInt32 := 0;
   begin
      -- Reset controller fields explicitly
      TWI_Periph.CTRL.TWI_CTRL_EN     := 0;
      TWI_Periph.CTRL.TWI_CTRL_PRSC   := 0;
      TWI_Periph.CTRL.TWI_CTRL_CDIV   := 0;
      TWI_Periph.CTRL.TWI_CTRL_CLKSTR := 0;

      -- Enable controller
      TWI_Periph.CTRL.TWI_CTRL_EN := 1;

      -- Prescaler (3 bits)
      TWI_Periph.CTRL.TWI_CTRL_PRSC := neorv32.UInt3 (PreScaler mod 8);

      -- Clock divider (4 bits)
      TWI_Periph.CTRL.TWI_CTRL_CDIV := neorv32.UInt4 (ClockDiv mod 16);

      -- Clock stretching
      if AllowClockStretching then
         TWI_Periph.CTRL.TWI_CTRL_CLKSTR := 1;
      else
         TWI_Periph.CTRL.TWI_CTRL_CLKSTR := 0;
      end if;
   end TWI_Setup;

   function TWI_Get_FIFO_Depth return Integer is
      Depth_Log2 : constant Natural := Natural (TWI_Periph.CTRL.TWI_CTRL_FIFO);
   begin
      if Depth_Log2 = 0 then
         return 0;
      else
         return Integer (2 ** Depth_Log2);
      end if;
   end TWI_Get_FIFO_Depth;

   procedure TWI_Enable is
   begin
      TWI_Periph.CTRL.TWI_CTRL_EN := 1;
   end TWI_Enable;

   procedure TWI_Disable is
   begin
      TWI_Periph.CTRL.TWI_CTRL_EN := 0;
   end TWI_Disable;

   function TWI_Sense_SDA return Boolean is
   begin
      return TWI_Periph.CTRL.TWI_CTRL_SENSE_SDA = 1;
   end TWI_Sense_SDA;

   function TWI_Sense_SCL return Boolean is --Make subtype of boolean for high/low
   begin
      return TWI_Periph.CTRL.TWI_CTRL_SENSE_SCL = 1;
   end TWI_Sense_SCL;

   function TWI_Busy return Boolean is
   begin
      return TWI_Periph.CTRL.TWI_CTRL_BUSY = 1;
   end TWI_Busy;

   --   /**********************************************************************//**
   --   * Get received data + ACK/NACH from RX FIFO.
   --   *
   --   * @param[in,out] data Pointer for returned data (uint8_t).
   --   * @return RX FIFO access status (-1 = no data available, 0 = ACK received, 1 = NACK received).
   --   Should use return enum
   --   **************************************************************************/
   function TWI_Get (Data : out Integer) return Integer is
      Tmp : neorv32.Byte;
   begin
      -- No RX data available
      if TWI_Periph.CTRL.TWI_CTRL_RX_AVAIL = 0 then
         return -1;
      end if;

      -- Reading DCMD pops RX FIFO
      Tmp := TWI_Periph.DCMD.TWI_DCMD;
      Data := Integer (Tmp);

      -- Return ACK/NACK (0 = ACK, 1 = NACK)
      return Integer (TWI_Periph.DCMD.TWI_DCMD_ACK);
   end TWI_Get;

   --   * @return 0: ACK received, 1: NACK received.
   --  Replace Ack_Next type and return type with Enum for Ack or subtype boolean
   function TWI_Transfer (Data : in out Integer; Ack_Next : in Boolean) return Integer is
   begin
      -- Wait for free TX FIFO entry
      while TWI_Periph.CTRL.TWI_CTRL_TX_FULL = 1 loop
         null;
      end loop;

      -- Send byte
      TWI_Send_Nonblocking (Data, Ack_Next);

      -- Wait until bus engine idle
      while TWI_Periph.CTRL.TWI_CTRL_BUSY = 1 loop
         null;
      end loop;

      -- Receive byte + ACK/NACK
      return TWI_Get (Data);
   end TWI_Transfer;

   procedure TWI_Generate_Start is
   begin
      -- Wait for free TX entry
      while TWI_Periph.CTRL.TWI_CTRL_TX_FULL = 1 loop
         null;
      end loop;

      TWI_Generate_Start_Nonblocking;

      -- Wait until idle again
      while TWI_Periph.CTRL.TWI_CTRL_BUSY = 1 loop
         null;
      end loop;
   end TWI_Generate_Start;

   procedure TWI_Generate_Stop is
   begin
      -- Wait for free TX entry
      while TWI_Periph.CTRL.TWI_CTRL_TX_FULL = 1 loop
         null;
      end loop;

      TWI_Generate_Stop_Nonblocking;

      -- Wait until idle again
      while TWI_Periph.CTRL.TWI_CTRL_BUSY = 1 loop
         null;
      end loop;
   end TWI_Generate_Stop;

   procedure TWI_Send_Nonblocking (Data : in Integer; Ack_Next : in Boolean) is
      Cmd : DCMD_Register;
   begin
      Cmd := (
         TWI_DCMD     => Byte (Data mod 256),
         TWI_DCMD_ACK => (if Ack_Next then 1 else 0),
         TWI_DCMD_CMD => TWI_CMD_RTX,
         others       => 0
      );
      TWI_Periph.DCMD := Cmd;
   end TWI_Send_Nonblocking;

   procedure TWI_Generate_Start_Nonblocking is
   begin
      TWI_Periph.DCMD.TWI_DCMD_CMD := TWI_CMD_START;
   end TWI_Generate_Start_Nonblocking;

   procedure TWI_Generate_Stop_Nonblocking is
   begin
      TWI_Periph.DCMD.TWI_DCMD_CMD := TWI_CMD_STOP;
   end TWI_Generate_Stop_Nonblocking;

   procedure Print_Hex_Byte (Data : UInt16) is
      Symbols : constant String := "0123456789abcdef";
   begin
      Ada.Text_IO.Put (Symbols (Integer (Shift_Right (Data, 4) and 16#0F#) + 1));
	   Ada.Text_IO.Put (Symbols (Integer (Data and 16#0F#) + 1));
   end Print_Hex_Byte;

   procedure Scan_TWI is
	   I : UInt16;
   	Num_Devices : Integer := 0;
      Data : UInt16;
   	TWI_Ack : Integer;
   begin
   	Ada.Text_IO.Put_Line ("Scanning TWI bus...");

   	for I in 0 .. 127 loop
   	   TWI_Generate_Start;
   		Data := UInt16 (2 * I + 1);
   	   TWI_Ack := TWI_Transfer (Integer (Data), False);
   	   TWI_Generate_Stop;

   		if TWI_Ack = 0 then
   			Ada.Text_IO.Put (" + Found device at write address 0x");
   		   Print_Hex_Byte (UInt16 (2 * I));
   			Ada.Text_IO.Put_Line ("");
   			Num_Devices := Num_Devices + 1;
   		end if;
   	end loop;

   	if Num_Devices = 0 then
   		Ada.Text_IO.Put_Line ("No devices found.");
   	else
   		Ada.Text_IO.Put ("Devices found: ");
   		Ada.Text_IO.Put (Num_Devices'Image);
   	end if;
   end Scan_TWI;

end TWI;
