with Ada.Text_IO;

procedure helios is
   procedure Print (Text : String) is
   begin
      Ada.Text_IO.Put_Line (Text);
   end Print;

   Text : String := "Hello Ada World!";
begin
   Print (Text);
   Text := "xxxxx xxx xxxxx.";
   Print (Text);
end helios;
