with Interfaces.C;

procedure Gnat_Exit (Code : Interfaces.C.int) is
begin
   -- Called when the Ada runtime wants to "exit".
   -- On bare metal, just never return (or later trigger a reset).
   loop
      null;
   end loop;
end Gnat_Exit;
