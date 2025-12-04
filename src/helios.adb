with Ada.Text_IO;
with Uart0;

with PWM_API;   use PWM_API;
with GPIO_API;  use GPIO_API;

with neorv32;       use neorv32;
with neorv32.TWI;
with RISCV.CSR;     use RISCV.CSR;
with Interrupts;    use Interrupts;
with TWI_API;
with Gnat_Exit;
procedure Helios is

   ----------------------------------------------------------------------------
   -- Camera clock using your PWM API
   ----------------------------------------------------------------------------
   Cam_External_Clock : PWM_T      := Create (Channel => 0);
   RESET_PIN          : GPIO_Pin_T := Create_Pin (11);

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
   -- DCMD command codes (bits 10:9 of DCMD)
   ----------------------------------------------------------------------------
   CMD_NOP   : constant := 2#00#;  -- 00
   CMD_START : constant := 2#01#;  -- 01
   CMD_STOP  : constant := 2#10#;  -- 10
   CMD_TRX   : constant := 2#11#;  -- 11

begin
   ----------------------------------------------------------------------------
   -- Interrupt system init (no FIRQ enabled yet)
   ----------------------------------------------------------------------------
   Ada.Text_IO.Put_Line ("Initializing interrupt system...");
   Interrupts.Init;
   TWI_API.Init_IRQ (Hart => 0);  -- installs TWI IRQ handler, but does not enable mie bit

   ----------------------------------------------------------------------------
   -- Camera clock
   ----------------------------------------------------------------------------
   Ada.Text_IO.Put_Line ("Initializing Camera Clock...");
   RESET_PIN.Set;

   Cam_External_Clock.Set_Hz (25_000_000.0);
   Cam_External_Clock.Set_Duty_Cycle (0.5);
   Cam_External_Clock.Enable;

   Ada.Text_IO.Put_Line ("Camera Clock ON (25MHz)");
   Ada.Text_IO.Put_Line ("Initializing TWI/I2C...");

   ----------------------------------------------------------------------------
   -- Configure TWI controller (CTRL register at 0xFFF90000)
   ----------------------------------------------------------------------------
   TWI.CTRL.TWI_CTRL_EN     := 0;
   TWI.CTRL.TWI_CTRL_PRSC   := 3;  -- prescaler (adjust as needed)
   TWI.CTRL.TWI_CTRL_CDIV   := 3;  -- fine divider (adjust as needed)
   TWI.CTRL.TWI_CTRL_CLKSTR := 1;  -- allow clock stretching if slave uses it
   TWI.CTRL.TWI_CTRL_EN     := 1;  -- enable TWI

   ----------------------------------------------------------------------------
   -- Enable TWI interrupt (FIRQ7) and global machine interrupts
   ----------------------------------------------------------------------------
   -- FIRQs are in mie bits 16..31. TWI is FIRQ channel 7 -> bit 16 + 7 = 23
   Mie.Set_Bits (Shift_Left (1, 16 + 7));
   Global_Machine_Interrupt_Enable;

   ----------------------------------------------------------------------------
   -- Single interrupt-based test:
   --   1) START
   --   2) Send OV5640 address byte (write)
   --   3) Wait for TWI IRQ (Ready := True)
   --   4) Read ACK bit from DCMD
   --   5) STOP
   ----------------------------------------------------------------------------
   declare
      Cmd     : neorv32.TWI.DCMD_Register;
      Reg     : neorv32.TWI.DCMD_Register;
      Timeout : constant Natural := 10_000_000;
      Count   : Natural := 0;
   begin
      Ada.Text_IO.Put_Line ("Starting TWI interrupt-based address write test...");

      -- Make sure Ready is clear before we start the operation
      TWI_API.Ready := False;

      -------------------------------------------------------------------------
      -- 1) Generate START condition (CMD = 01)
      -------------------------------------------------------------------------
      Cmd.TWI_DCMD      := 0;          -- data not used for START
      Cmd.TWI_DCMD_ACK  := 0;          -- don't care here
      Cmd.TWI_DCMD_CMD  := CMD_START;  -- 01 = START
      TWI.DCMD := Cmd;

      -------------------------------------------------------------------------
      -- 2) Transmit OV5640 address byte (write) and sample ACK
      -------------------------------------------------------------------------
      -- After this TRX operation completes, the TWI IRQ should fire once.
      TWI_API.Ready := False;  -- ensure we wait for THIS operation

      Cmd.TWI_DCMD      := neorv32.Byte (OV5640_Addr_WR);  -- address byte
      Cmd.TWI_DCMD_ACK  := 0;   -- controller does not ACK, we read slave ACK later
      Cmd.TWI_DCMD_CMD  := CMD_TRX;                        -- 11 = data TRX
      TWI.DCMD := Cmd;

      -------------------------------------------------------------------------
      -- 3) Wait (bounded) for the TWI IRQ handler to set Ready = True
      -------------------------------------------------------------------------
      while (not TWI_API.Ready) and then (Count < Timeout) loop
         Count := Count + 1;
      end loop;

      if Count = Timeout then
         Ada.Text_IO.Put_Line ("ERROR: TWI interrupt timeout (no idle interrupt).");
      else
         ----------------------------------------------------------------------
         -- 4) Read DCMD to check the ACK bit:
         --     TWI_DCMD_ACK = 0 -> device ACK
         --     TWI_DCMD_ACK = 1 -> device NACK
         ----------------------------------------------------------------------
         Reg := TWI.DCMD;  -- real hardware read of DCMD register

         if Reg.TWI_DCMD_ACK = 0 then
            Ada.Text_IO.Put_Line ("SUCCESS: IRQ fired and OV5640 ACKed address.");
         else
            Ada.Text_IO.Put_Line ("IRQ fired but NO ACK from OV5640 (NACK).");
         end if;
      end if;

      -------------------------------------------------------------------------
      -- 5) Generate STOP condition (CMD = 10) to leave the bus clean
      -------------------------------------------------------------------------
      TWI_API.Ready := False;
      Cmd.TWI_DCMD      := 0;
      Cmd.TWI_DCMD_ACK  := 0;
      Cmd.TWI_DCMD_CMD  := CMD_STOP;   -- 10 = STOP
      TWI.DCMD := Cmd;
   end;

   Ada.Text_IO.Put_Line ("Helios done. Entering idle loop.");
    ----------------------------------------------------------------------------
    -- On bare-metal / bare_runtime there is no "exit()", so just idle.
    ----------------------------------------------------------------------------
   loop
      null;
   end loop;

end Helios;
