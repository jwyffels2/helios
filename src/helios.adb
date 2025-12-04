with Ada.Text_IO;
with Gnat_Exit;
with Uart0;

with PWM_API;  use PWM_API;
with GPIO_API;  use GPIO_API;

with neorv32;use neorv32;
with neorv32.TWI;

procedure Helios is

   ----------------------------------------------------------------------------
   -- Camera clock using your PWM API
   ----------------------------------------------------------------------------
   Cam_External_Clock : PWM_T := Create (Channel => 0);
    RESET_PIN : GPIO_Pin_T := Create_Pin (11);
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
    RESET_PIN.Set;

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
   TWI.CTRL.TWI_CTRL_PRSC   := 3;
   TWI.CTRL.TWI_CTRL_CDIV   := 3;  -- fine divider
   TWI.CTRL.TWI_CTRL_CLKSTR := 1;   -- clock stretching disabled (enable if needed)

   -- Enable TWI after configuration
   TWI.CTRL.TWI_CTRL_EN     := 1;


   ----------------------------------------------------------------------------
   -- Probe OV5640 until it ACKs
   ----------------------------------------------------------------------------
   declare
      Cmd : neorv32.TWI.DCMD_Register;
      Reg : neorv32.TWI.DCMD_Register;
   begin
      loop
         Ada.Text_IO.Put_Line ("Probing OV5640...");

         ---------------------------------------------------------------------
         -- START
         ---------------------------------------------------------------------
         Cmd.TWI_DCMD_CMD := CMD_START;
         TWI.DCMD := Cmd;
         TWI_Wait_Ready;

         ---------------------------------------------------------------------
         -- Transmit OV5640 I2C address (write)
         ---------------------------------------------------------------------
         Cmd.TWI_DCMD     := neorv32.Byte (OV5640_Addr_WR); -- address byte
         Cmd.TWI_DCMD_ACK := 0;                             -- let slave ACK/NACK
         Cmd.TWI_DCMD_CMD := CMD_TRX;                       -- transmit command
         TWI.DCMD := Cmd;
         TWI_Wait_Ready;

         ---------------------------------------------------------------------
         -- Check ACK
         ---------------------------------------------------------------------
         Reg := TWI.DCMD;  -- full 32-bit read
         if Reg.TWI_DCMD_ACK = 0 then
            Ada.Text_IO.Put_Line ("OV5640 ACK received! Communication OK.");
            exit;  -- got it, leave the loop
         else
            Ada.Text_IO.Put_Line ("NO ACK from OV5640, retrying...");

            -- STOP before retrying
            Cmd.TWI_DCMD_CMD := CMD_STOP;
            TWI.DCMD := Cmd;
            TWI_Wait_Ready;
         end if;
      end loop;

      -------------------------------------------------------------------------
      -- Final STOP after successful probe (optional but clean)
      -------------------------------------------------------------------------
      Cmd.TWI_DCMD_CMD := CMD_STOP;
      TWI.DCMD := Cmd;
      TWI_Wait_Ready;
   end;

   Ada.Text_IO.Put_Line ("TWI test complete.");

end Helios;
