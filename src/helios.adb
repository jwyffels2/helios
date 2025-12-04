with VGA;
with Interfaces; use Interfaces;
with Gnat_Exit;
procedure helios is
begin
   -- Turn VGA on
   VGA.Enable;

   -- Set background to some color: R=15, G=0, B=8
   VGA.Set_Background (R => 15, G => 0, B => 8);

   -- Simple color cycling loop (optional)
   declare
      R, G, B : Unsigned_8 := 0;
   begin
      loop
         VGA.Set_Background (R, G, B);

         -- very crude delay (busy loop)
         for I in 1 .. 200_000 loop
            null;
         end loop;

         R := (R + 1) mod 16;
         G := (G + 1) mod 16;
         B := (B + 1) mod 16;
      end loop;
   end;
end helios;
