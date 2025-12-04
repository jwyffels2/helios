with Ada.Text_IO;
with Gnat_Exit;
with Uart0;

with PWM_API;  use PWM_API;

with neorv32;use neorv32;
with neorv32.TWI;

procedure Helios is

   ----------------------------------------------------------------------------
   -- Camera clock using your PWM API
   ----------------------------------------------------------------------------
   Cam_External_Clock : PWM_T := Create (Channel => 0);

   ----------------------------------------------------------------------------
   -- TWI peripheral (rename only, no alias)
   ----------------------------------------------------------------------------
   TWI : neorv32.TWI.TWI_Peripheral renames neorv32.TWI.TWI_Periph;

   ----------------------------------------------------------------------------
   -- OV5640 camera I2C address
   -- OV5640 7-bit address = 0x3C -> write address = 0x78
   ----------------------------------------------------------------------------
   OV5640_Addr_WR : constant := 16#78#;

   ----------------------------------------------------------------------------
   -- DCMD command codes
   ----------------------------------------------------------------------------
   CMD_NOP   : constant := 2#00#;
   CMD_START : constant := 2#01#;
   CMD_STOP  : constant := 2#10#;
   CMD_TRX   : constant := 2#11#;

   ----------------------------------------------------------------------------
   -- Small helper: wait until TWI is not busy
   ----------------------------------------------------------------------------
   procedure TWI_Wait_Ready is
   begin
      while TWI.CTRL.TWI_CTRL_BUSY = 1 loop
         null;
      end loop;
   end TWI_Wait_Ready;

begin
   Ada.Text_IO.Put_Line ("Initializing Camera Clock...");

   Cam_External_Clock.Set_Hz (25_000_000.0);
   Cam_External_Clock.Set_Duty_Cycle (0.5);
   Cam_External_Clock.Enable;

   Ada.Text_IO.Put_Line ("Camera Clock ON (25MHz)");
   Ada.Text_IO.Put_Line ("Initializing TWI/I2C...");

   ----------------------------------------------------------------------------
   -- Configure TWI controller
   -- Do configuration with EN = 0, then enable.
   -- PRSC = 4 -> prescaler = 128 (per datasheet table)
   -- CDIV = 15 -> adjust for your desired fSCL using:
   --   fSCL = fmain / (4 * prescaler * (1 + CDIV))
   ----------------------------------------------------------------------------
   TWI.CTRL.TWI_CTRL_EN     := 0;
   TWI.CTRL.TWI_CTRL_PRSC   := 4;   -- 0b100 -> prescaler = 128
   TWI.CTRL.TWI_CTRL_CDIV   := 15;  -- fine divider
   TWI.CTRL.TWI_CTRL_CLKSTR := 0;   -- clock stretching disabled (enable if needed)

   -- Enable TWI after configuration
   TWI.CTRL.TWI_CTRL_EN     := 1;


   ----------------------------------------------------------------------------
   -- Send START (single 32-bit DCMD write)
   ----------------------------------------------------------------------------
   declare
      Cmd : neorv32.TWI.DCMD_Register;
   begin
      Cmd.TWI_DCMD_CMD := CMD_START;
      TWI.DCMD := Cmd;
   end;

   TWI_Wait_Ready;

   ----------------------------------------------------------------------------
   -- Transmit OV5640 I2C address (write)
   -- DCMD is written ONCE as a full record to avoid unintended reads/partial writes.
   ----------------------------------------------------------------------------
   declare
      Cmd : neorv32.TWI.DCMD_Register;
   begin
      Cmd.TWI_DCMD     := neorv32.Byte (OV5640_Addr_WR);  -- address byte
      Cmd.TWI_DCMD_ACK := 0;                              -- let slave send ACK/NACK
      Cmd.TWI_DCMD_CMD := CMD_TRX;                        -- data transmission command
      TWI.DCMD := Cmd;                                    -- single 32-bit write
   end;

   TWI_Wait_Ready;

   ----------------------------------------------------------------------------
   -- TRUE HARDWARE ACK/NACK CHECK
   -- Must read the entire DCMD register (32-bit) due to Volatile_Full_Access
   -- and the "*** modified following a read operation ***" semantics.
   ----------------------------------------------------------------------------
   declare
      Reg : neorv32.TWI.DCMD_Register := TWI.DCMD;  -- real hardware read
   begin
      if Reg.TWI_DCMD_ACK = 0 then
         Ada.Text_IO.Put_Line ("OV5640 ACK received! Communication OK.");
      else
         Ada.Text_IO.Put_Line ("NO ACK from OV5640 (device not found).");
      end if;
   end;

   ----------------------------------------------------------------------------
   -- STOP (again: build a local DCMD and write it once)
   ----------------------------------------------------------------------------
   declare
      Cmd : neorv32.TWI.DCMD_Register;
   begin
      Cmd.TWI_DCMD_CMD := CMD_STOP;
      TWI.DCMD := Cmd;
   end;

   TWI_Wait_Ready;

   Ada.Text_IO.Put_Line ("TWI test complete.");

end Helios;
