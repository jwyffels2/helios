with Uart0;
with Gnat_Exit;
with PWM_API;  use PWM_API;
with GPIO_API; use GPIO_API;
with neorv32;  use neorv32;
with neorv32.TWI; use neorv32.TWI;
with TWI; use TWI;

procedure Helios is
   -- Create PWM
   Pwm0: PWM_T := PWM_API.Create (Channel => 0);
begin

   Pwm0.Configure (Target_Hz => 25_000_000.0, Duty => 0.5);
   Pwm0.Enable;

   TWI.TWI_Setup (preScaler => 6, clockDiv => 15, allowClockStretching => False);
   TWI.Scan_TWI;

end Helios;
