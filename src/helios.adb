with Ada.Text_IO;
with Uart0;
with Gnat_Exit;
with neorv32; use neorv32;
with neorv32.GPIO;
with neorv32.SYSINFO;
with neorv32.GPTMR;
with neorv32.PWM;
procedure Helios is

   Clock_Hz : constant UInt32 := neorv32.SYSINFO.SYSINFO_Periph.CLK;  -- e.g. 100_000_000

   -- GPTMR prescaler = f/128  (PRSC = 4 according to NEORV32 docs)
   Ticks_Per_Second : constant UInt32 := Clock_Hz / 128;

   LED_Mask : constant neorv32.UInt32 :=
     2#0000_0000_0000_0000_0000_0000_1000_1111#;

   -- wait for ~1 second using GPTMR in single-shot mode
   procedure Wait_One_Second is
   begin
      -- set threshold
      neorv32.GPTMR.GPTMR_Periph.THRES := Ticks_Per_Second;

      -- clear any old pending interrupt
      neorv32.GPTMR.GPTMR_Periph.CTRL.GPTMR_CTRL_IRQ_CLR := 1;

      -- configure mode and prescaler
      neorv32.GPTMR.GPTMR_Periph.CTRL.GPTMR_CTRL_PRSC := 4;  -- f/128

      -- enable the timer
      neorv32.GPTMR.GPTMR_Periph.CTRL.GPTMR_CTRL_EN := 1;

      -- poll until threshold reached
      while neorv32.GPTMR.GPTMR_Periph.CTRL.GPTMR_CTRL_IRQ_PND = 0 loop
         null;
      end loop;

      -- ack/clear pending flag (and optionally stop timer)
      neorv32.GPTMR.GPTMR_Periph.CTRL.GPTMR_CTRL_IRQ_CLR := 1;
      neorv32.GPTMR.GPTMR_Periph.CTRL.GPTMR_CTRL_EN      := 0;
   end Wait_One_Second;

   -- "Seconds" is now N * real timer seconds
   procedure Timer (Seconds : UInt32) is
   begin
      for S in 1 .. Seconds loop
         Wait_One_Second;
      end loop;
   end Timer;

begin
   Ada.Text_IO.Put_Line ("Hello");

    neorv32.GPIO.GPIO_Periph.PORT_OUT := LED_Mask;
   loop
      Timer (1);
      -- clean toggle of only the LED bits
      neorv32.GPIO.GPIO_Periph.PORT_OUT := neorv32.GPIO.GPIO_Periph.PORT_OUT xor LED_Mask;


   end loop;
end Helios;
