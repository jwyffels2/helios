with neorv32; use neorv32;
with neorv32.TWI; use neorv32.TWI;

package TWI is
   subtype TWI_Command is neorv32.TWI.DCMD_TWI_DCMD_CMD_Field;
   TWI_CMD_NOP   : constant TWI_Command := 0;
   TWI_CMD_START : constant TWI_Command := 1;
   TWI_CMD_STOP  : constant TWI_Command := 2;
   TWI_CMD_RTX   : constant TWI_Command := 3;

   function twi_available return Boolean;
   procedure TWI_Setup (preScaler : Natural; clockDiv : Natural; allowClockStretching : Boolean);
   function  twi_get_fifo_depth return Integer;
   procedure twi_disable;
   procedure twi_enable;

   function  twi_sense_scl return Boolean; --Make subtype of boolean for high/low
   function  twi_sense_sda return Boolean;

   function twi_busy return Boolean;

   --   /**********************************************************************//**
   --   * Get received data + ACK/NACH from RX FIFO.
   --   *
   --   * @param[in,out] data Pointer for returned data (uint8_t).
   --   * @return RX FIFO access status (-1 = no data available, 0 = ACK received, 1 = NACK received).
   --   Should use return enum
   --   **************************************************************************/
   function TWI_Get (Data : out Integer) return Integer;

   --   * @return 0: ACK received, 1: NACK received.
   --  Replace Ack_Next type and return type with Enum for Ack or subtype boolean
   function TWI_Transfer (Data : in out Integer; Ack_Next : in Boolean) return Integer;
   procedure TWI_Generate_Start;
   procedure TWI_Generate_Stop;

   procedure TWI_Send_Nonblocking (Data : in Integer; Ack_Next : in Boolean);
   procedure TWI_Generate_Start_Nonblocking;
   procedure TWI_Generate_Stop_Nonblocking;

   procedure Print_Hex_Byte (Data : UInt16);
   procedure Scan_TWI;
end TWI;
