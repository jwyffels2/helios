with Uart0;
with Gnat_Exit;
with PWM_API; use PWM_API;

procedure Helios is
   -- Create PWM
   Pwm0 : PWM_T := Create(Channel => 0);
begin
   -- Configure PWM
   Pwm0.Set_Hz(5.0);
   Pwm0.Set_Duty_Cycle(0.5);
   Pwm0.Enable;

end Helios;
}
