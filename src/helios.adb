with Ada.Text_IO;
with Gnat_Exit;
with Uart0;

with PWM_API;  use PWM_API;
with GPIO_API;  use GPIO_API;

with neorv32;use neorv32;
with neorv32.TWI; use neorv32.TWI;

procedure Helios is

   ----------------------------------------------------------------------------
   -- Camera clock using your PWM API
   ----------------------------------------------------------------------------
   Cam_External_Clock : PWM_T := Create (Channel => 0);
    RESET_PIN : GPIO_Pin_T := Create_Pin (11);
   ----------------------------------------------------------------------------
   -- TWI peripheral (rename only, no alias)
   ----------------------------------------------------------------------------
   -- TWI : neorv32.TWI.TWI_Peripheral renames TWI_Periph;

   ----------------------------------------------------------------------------
   -- OV5640 camera I2C address
   -- OV5640 7-bit address = 0x3C -> write address = 0x78
   ----------------------------------------------------------------------------
   OV5640_Addr_WR : neorv32.Byte := 16#79#;

   ----------------------------------------------------------------------------
   -- DCMD command codes
   ----------------------------------------------------------------------------
   CMD_NOP   : UInt2 := 2#00#;
   CMD_START : UInt2 := 2#01#;
   CMD_STOP  : UInt2 := 2#10#;
   CMD_TRX   : UInt2 := 2#11#;

   ----------------------------------------------------------------------------
   -- Small helper: wait until TWI is not busy
   ----------------------------------------------------------------------------
   procedure TWI_Wait_Ready is
   begin
      while TWI_Periph.CTRL.TWI_CTRL_RX_AVAIL = 0 loop
         null;
      end loop;
   end TWI_Wait_Ready;

begin
   Ada.Text_IO.Put_Line ("Initializing Camera Clock...");
    RESET_PIN.Set;

   Configure (Cam_External_Clock, 25_000_000.0, 0.5);
   Enable(Cam_External_Clock);

   Ada.Text_IO.Put_Line ("Camera Clock ON (25MHz)");
   Ada.Text_IO.Put_Line ("Initializing TWI/I2C...");

   ----------------------------------------------------------------------------
   -- Configure TWI controller
   --   fSCL = fmain / (4 * prescaler * (1 + CDIV))
   ----------------------------------------------------------------------------
   TWI_Periph.CTRL.TWI_CTRL_EN     := 0;
   TWI_Periph.CTRL.TWI_CTRL_PRSC   := 3;
   TWI_Periph.CTRL.TWI_CTRL_CDIV   := 3;  -- fine divider
   TWI_Periph.CTRL.TWI_CTRL_CLKSTR := 0;  -- clock stretching disabled (enable if needed)

   -- Enable TWI after configuration
   TWI_Periph.CTRL.TWI_CTRL_EN     := 1;


   ----------------------------------------------------------------------------
   -- Probe OV5640 until it ACKs
   ----------------------------------------------------------------------------

    Ada.Text_IO.Put_Line ("Probing OV5640...");

    ---------------------------------------------------------------------
    -- START
    ---------------------------------------------------------------------
    TWI_Periph.DCMD.TWI_DCMD_CMD := CMD_START;

    ---------------------------------------------------------------------
    -- Transmit OV5640 I2C address (write)
    ---------------------------------------------------------------------
    TWI_Periph.DCMD.TWI_DCMD   := OV5640_Addr_WR; -- address byte
    TWI_Periph.DCMD.TWI_DCMD_ACK := 0;   -- let slave ACK/NACK
    TWI_Periph.DCMD.TWI_DCMD_CMD := CMD_TRX;  -- transmit command
    TWI_Wait_Ready;

    ---------------------------------------------------------------------
    -- Check ACK
    ---------------------------------------------------------------------
    if TWI_Periph.DCMD.TWI_DCMD_ACK = 0 then
        Ada.Text_IO.Put_Line ("OV5640 ACK received! Communication OK.");
    else
        Ada.Text_IO.Put_Line ("NO ACK from OV5640, retrying...");

    --  -- STOP before retrying
    --  TWI_Periph.DCMD.TWI_DCMD_CMD := CMD_STOP;
    --  TWI_Periph.DCMD := Cmd;
    --  TWI_Wait_Ready;
    end if;


    -------------------------------------------------------------------------
    -- Final STOP after successful probe (optional but clean)
    -------------------------------------------------------------------------
    TWI_Periph.DCMD.TWI_DCMD_CMD := CMD_STOP;
    TWI_Wait_Ready;

   Ada.Text_IO.Put_Line ("TWI test complete.");

end Helios;
