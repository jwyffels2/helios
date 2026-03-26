with Ada.Text_IO;
with Uart0;
with Gnat_Exit;
with PWM_API;     use PWM_API;
with GPIO_API;    use GPIO_API;
with neorv32;     use neorv32;
with neorv32.TWI; use neorv32.TWI;
with TWI_API;     use TWI_API;
with I2C_API;     use I2C_API;

procedure Helios is
   -- Create PWM
   Pwm0 : PWM_T := PWM_API.Create (Channel => 0);
   CAMERA_ADDRESS: I2C_Addr7 := 16#3C#;
   TEST_PATTERN_REGISTER : UInt16 := 16#503D#;
   TEST_PATTERN_CONFIG   : Integer := 2#10000000#;
   pingResponse : Boolean;
   testPatternResponse : Integer;
   output : String := "";
begin

   Pwm0.Configure (Target_Hz => 25_000_000.0, Duty => 0.5);
   Pwm0.Enable;

   TWI_API.TWI_Setup (Prescaler => 6, Clock_Div => 15, Allow_Clock_Stretching => False);
--     TWI_API.Scan_TWI;
   --  pingResponse := I2C_API.I2C_Ping (CAMERA_ADDRESS);
   --  if pingResponse then
   --      Ada.Text_IO.Put_Line ("Ping Response Recieved");
   --  else
   --      Ada.Text_IO.Put_Line ("Something is wrong!");
   --  end if;

   I2C_API.I2C_Write (Device_Address => CAMERA_ADDRESS, Register => TEST_PATTERN_REGISTER, Value => TEST_PATTERN_CONFIG);
   if I2C_API.I2C_Read (Device_Address => CAMERA_ADDRESS, Register => TEST_PATTERN_REGISTER) = TEST_PATTERN_CONFIG then
      Ada.Text_IO.Put_Line ("Set Register Properly");
   else
      Ada.Text_IO.Put_Line ("Does Not Work Sir");

      --  output := I2C_API.I2C_Read (Device_Address => CAMERA_ADDRESS, Register => TEST_PATTERN_REGISTER)'Image;
   end if;

   --  Ada.Text_IO.Put_Line ("Chip ID High:" &
   --      I2C_Read (CAMERA_ADDRESS, 16#300A#)'Image);

   --  Ada.Text_IO.Put_Line ("Chip ID Low:" &
   --      I2C_Read (CAMERA_ADDRESS, 16#300B#)'Image);

end Helios;
