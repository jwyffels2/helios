with Gnat_Exit;
with Uart0;
with PWM_API; use PWM_API;

procedure Helios is
   Pwm0 : PWM_T := Create (Channel => 0);
begin
   Uart0.Init (115200);
   Pwm0.Configure (Target_Hz => 5.0, Duty => 0.5);
   Pwm0.Enable;
end Helios;
