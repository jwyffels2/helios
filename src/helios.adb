with Uart0;
with Gnat_Exit;
with PWM_API;  use PWM_API;
with GPIO_API; use GPIO_API;
with neorv32;  use neorv32;
with neorv32.TWI; use neorv32.TWI;
with Ada.Text_IO;

procedure Helios is
   -- Create PWM
   Pwm0      : PWM_T := Create(Channel => 0);
   RESET_PIN : GPIO_Pin_T := Create_Pin (11);

   ----------------------------------------------------------------------------
   -- OV5640 camera I2C address
   -- 7-bit address = 0x3C -> write address byte = 0x78
   ----------------------------------------------------------------------------
   OV5640_Addr_WR : neorv32.Byte := 16#78#;

   ----------------------------------------------------------------------------
   -- DCMD command codes (NEORV32 TWI)
   ----------------------------------------------------------------------------
   CMD_NOP   : UInt2 := 2#00#;
   CMD_START : UInt2 := 2#01#;
   CMD_STOP  : UInt2 := 2#10#;
   CMD_TRX   : UInt2 := 2#11#;

   ----------------------------------------------------------------------------
   -- Wait until TWI engine is idle (BUSY=0)
   ----------------------------------------------------------------------------
   procedure TWI_Wait_Ready is
   begin
      while TWI_Periph.CTRL.TWI_CTRL_BUSY = 1 loop
         null;
      end loop;
   end TWI_Wait_Ready;

   ----------------------------------------------------------------------------
   -- Wait until TX FIFO has space
   ----------------------------------------------------------------------------
   procedure TWI_Wait_Tx_Space is
   begin
      while TWI_Periph.CTRL.TWI_CTRL_TX_FULL = 1 loop
         null;
      end loop;
   end TWI_Wait_Tx_Space;

   ----------------------------------------------------------------------------
   -- Send START + address(write) + STOP, return True if ACKed
   ----------------------------------------------------------------------------
   function Probe_OV5640 return Boolean is
   begin
      -- START
      TWI_Periph.DCMD.TWI_DCMD_CMD := CMD_START;
      TWI_Wait_Ready;

      -- Send address byte
      TWI_Wait_Tx_Space;
      TWI_Periph.DCMD.TWI_DCMD     := OV5640_Addr_WR;
      TWI_Periph.DCMD.TWI_DCMD_CMD := CMD_TRX;
      TWI_Wait_Ready;

      -- ACK bit: 0 = ACK, 1 = NACK
      declare
         Acked : constant Boolean := (TWI_Periph.DCMD.TWI_DCMD_ACK = 0);
      begin
         -- STOP (always)
         TWI_Periph.DCMD.TWI_DCMD_CMD := CMD_STOP;
         TWI_Wait_Ready;
         return Acked;
      end;
   end Probe_OV5640;

begin
   -- Configure PWM (camera clock)
   Pwm0.Configure (25_000_000.0, 0.5);
   Pwm0.Enable;

   Ada.Text_IO.Put_Line ("Initializing Camera Clock...");
   RESET_PIN.Set;
   Ada.Text_IO.Put_Line ("Camera Clock ON (25MHz)");
   Ada.Text_IO.Put_Line ("Initializing TWI/I2C...");

   ----------------------------------------------------------------------------
   -- Configure TWI controller
   ----------------------------------------------------------------------------
   TWI_Periph.CTRL.TWI_CTRL_EN     := 0;
   TWI_Periph.CTRL.TWI_CTRL_PRSC   := 3;
   TWI_Periph.CTRL.TWI_CTRL_CDIV   := 3;
   TWI_Periph.CTRL.TWI_CTRL_CLKSTR := 1; -- enable stretching is usually safer
   TWI_Periph.CTRL.TWI_CTRL_EN     := 1;

   Ada.Text_IO.Put_Line ("Probing OV5640...");

   -- Try a few times (sensor might not be ready immediately after reset/clock)
   for Attempt in 1 .. 10 loop
      if Probe_OV5640 then
         Ada.Text_IO.Put_Line ("OV5640 ACK received! Communication OK.");
         exit;
      else
         Ada.Text_IO.Put_Line ("NO ACK from OV5640.");
      end if;
   end loop;

   Ada.Text_IO.Put_Line ("TWI test complete.");
end Helios;
