with Ada.Text_IO;
with Gnat_Exit;
with Uart0;

with PWM_API;  use PWM_API;

with neorv32; use neorv32;
with neorv32.TWI;

procedure Helios is

   ----------------------------------------------------------------------------
   -- Camera clock using your PWM API
   ----------------------------------------------------------------------------
   Cam_External_Clock : PWM_T := Create (Channel => 0);

   ----------------------------------------------------------------------------
   -- TWI peripheral alias
   ----------------------------------------------------------------------------
   TWI : neorv32.TWI.TWI_Peripheral renames neorv32.TWI.TWI_Periph;

   ----------------------------------------------------------------------------
   -- OV5640 camera I2C address
   ----------------------------------------------------------------------------
   OV5640_Addr_WR : constant := 16#78#;

   ----------------------------------------------------------------------------
   -- DCMD command codes
   ----------------------------------------------------------------------------
   CMD_NOP   : constant := 2#00#;
   CMD_START : constant := 2#01#;
   CMD_STOP  : constant := 2#10#;
   CMD_TRX   : constant := 2#11#;

begin
   Ada.Text_IO.Put_Line ("Initializing Camera Clock...");

   Cam_External_Clock.Set_Hz (25_000_000.0);
   Cam_External_Clock.Set_Duty_Cycle (0.5);
   Cam_External_Clock.Enable;

   Ada.Text_IO.Put_Line ("Camera Clock ON (25MHz)");
   Ada.Text_IO.Put_Line ("Initializing TWI/I2C...");

   ----------------------------------------------------------------------------
   -- Enable TWI controller (values must respect UInt3/UInt4 ranges!)
   ----------------------------------------------------------------------------
   TWI.CTRL.TWI_CTRL_EN    := 1;
   TWI.CTRL.TWI_CTRL_PRSC  := 6;   -- prescaler select (128)
   TWI.CTRL.TWI_CTRL_CDIV  := 15;  -- valid UInt4 max
   TWI.CTRL.TWI_CTRL_CLKSTR := 0;

   ----------------------------------------------------------------------------
   -- Send START
   ----------------------------------------------------------------------------
   TWI.DCMD.TWI_DCMD_CMD := CMD_START;

   while TWI.CTRL.TWI_CTRL_BUSY = 1 loop
      null;
   end loop;

   ----------------------------------------------------------------------------
   -- Transmit OV5640 I2C address (write)
   ----------------------------------------------------------------------------
   TWI.DCMD.TWI_DCMD      := neorv32.Byte (OV5640_Addr_WR);
   TWI.DCMD.TWI_DCMD_ACK  := 0;
   TWI.DCMD.TWI_DCMD_CMD  := CMD_TRX;

   while TWI.CTRL.TWI_CTRL_BUSY = 1 loop
      null;
   end loop;

   ----------------------------------------------------------------------------
   -- Check ACK (DCMD is volatile; read once to update flags)
   ----------------------------------------------------------------------------
   declare
      Dummy   : neorv32.Byte := TWI.DCMD.TWI_DCMD;
      Acked   : constant Boolean := (TWI.DCMD.TWI_DCMD_ACK = 0);
   begin
      if Acked then
         Ada.Text_IO.Put_Line ("OV5640 ACK received! Communication OK.");
      else
         Ada.Text_IO.Put_Line ("NO ACK from OV5640. Check wiring/power.");
      end if;
   end;

   ----------------------------------------------------------------------------
   -- STOP
   ----------------------------------------------------------------------------
   TWI.DCMD.TWI_DCMD_CMD := CMD_STOP;

   while TWI.CTRL.TWI_CTRL_BUSY = 1 loop
      null;
   end loop;

   Ada.Text_IO.Put_Line ("TWI test complete.");

end Helios;
