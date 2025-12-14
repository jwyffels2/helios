with VGA;
with Interfaces; use Interfaces;
with PWM_API;
with Uart0;
with Ada.Text_IO; use Ada.Text_IO;
with Gnat_Exit;
procedure Helios is
begin
   loop
      VGA.Enable;
      VGA.Set_Background (16#0#, 16#0#, 16#8#); -- blue-ish

      for I in 1 .. 100 loop
         Put_Line ("Forcing Delay");
      end loop;

      VGA.Set_Background (16#8#, 16#0#, 16#0#); -- red-ish

      for I in 1 .. 100 loop
         Put_Line ("Forcing Delay");
      end loop;

        VGA.Set_Background (16#0#, 16#8#, 16#0#); -- green-ish

      for I in 1 .. 100 loop
         Put_Line ("Forcing Delay");
      end loop;


   end loop;
end Helios;
