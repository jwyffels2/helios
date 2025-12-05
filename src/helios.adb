with VGA;
with Interfaces; use Interfaces;
with PWM_API;
with Gnat_Exit;
procedure helios is

begin

        -- Turn VGA on
        VGA.Enable;
        VGA.Set_Background (16#0#, 16#0#, 16#8#); -- blue-ish background

end helios;
