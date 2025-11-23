with Ada.Text_IO;
with Uart0;
with Gnat_Exit;
with neorv32; use neorv32;
with neorv32.GPIO;
with neorv32.SYSINFO;
with neorv32.GPTMR;
with neorv32.PWM; use neorv32.PWM;
procedure Helios is
   --  Constants for ~5 Hz from 100 MHz
   CLKPRSC_1024 : constant UInt32 := 5;      -- 0b101 -> prescaler = 1024
   TOP_5HZ      : constant UInt16 := 19531;  -- TOP + 1 = 19532
   CMP_50PCT    : constant UInt16 := 9766;   -- 50% duty: CMP / (TOP+1)

begin
   --  1) Disable channel 0 while configuring
   PWM_Periph.ENABLE := PWM_Periph.ENABLE and not 1;  -- clear bit 0

   --  2) Set global clock prescaler to 1024
   --     Only bits 2..0 are used.
   PWM_Periph.CLKPRSC := CLKPRSC_1024;

   --  3) Configure channel 0 TOP and CMP
   PWM_Periph.CHANNEL (0).TOPCMP.TOP := TOP_5HZ;
   PWM_Periph.CHANNEL (0).TOPCMP.CMP := CMP_50PCT;

   --  4) Normal (non-inverted) polarity on channel 0: clear bit 0
   PWM_Periph.POLARITY := PWM_Periph.POLARITY and not 1;

   --  5) Enable channel 0
   PWM_Periph.ENABLE := PWM_Periph.ENABLE or 1;

end Helios;
