with Ada.Text_IO;
-- with Interrupts; Commented out because we don't need to use interrupts unless we want to handle keyboard/async input
with Uart0; --Must be imported otherwise cannot print to screen, because UART is the protocol used to connect via terminal
with Gnat_Exit; --Must be imported/implemented so program knows how to exit
with neorv32; use neorv32; -- This must be used to be able to have access to special type compatibility etc
with neorv32.GPIO; -- Used to control LEDs and other GPIO
procedure Helios is
LED_Mask : constant neorv32.UInt32 := 2#0000_0000_0000_0000_0000_0000_0000_1111#;  -- gpio_o(0) LED0 On Basys3
begin
   Ada.Text_IO.Put_Line("Hello");
   neorv32.GPIO.GPIO_Periph.PORT_OUT := neorv32.GPIO.GPIO_Periph.PORT_OUT or LED_Mask;
   loop
      null;
   end loop;
end Helios;
