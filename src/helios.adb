with Uart0;
with Uart1;
with Gnat_Exit;
with Min;
with Coordinate_Listener;

procedure Helios is

    procedure Delay_Loop (Count : Natural) is
    begin
        for I in 1 .. Count loop
            null;
        end loop;
    end Delay_Loop;

    procedure Send_Command is
    begin
        while not Uart1.TX_Ready loop
            null;
        end loop;
        Uart1.Write_TX (Character'Val (16#56#));

        while not Uart1.TX_Ready loop
            null;
        end loop;
        Uart1.Write_TX (Character'Val (16#00#));

        while not Uart1.TX_Ready loop
            null;
        end loop;
        Uart1.Write_TX (Character'Val (16#26#));

        while not Uart1.TX_Ready loop
            null;
        end loop;
        Uart1.Write_TX (Character'Val (16#00#));
    end Send_Command;

    procedure Send_Test_Byte is
    begin
        while not Uart1.TX_Ready loop
            null;
        end loop;
        Uart1.Write_TX (Character'Val (16#55#));
    end Send_Test_Byte;

begin
    Uart0.Init (19200);
    Uart1.Init (38400);

    Coordinate_Listener.Init;

    Uart0.Put ("Boot ");

    loop
        --  Listen for coordinates
        Coordinate_Listener.Poll;

        --  Handle any available camera data
        if Uart1.RX_Ready then
            declare
                B : Integer := Character'Pos (Uart1.Read_RX);
            begin
                Uart0.Put ("RX:");
                Uart0.Put (Integer'Image (B));
                Uart0.Put (" ");
            end;
        end if;

        --  Uart0.Put ("SEND ");

        --  Send_Command;

        --  for I in 1 .. 20_000_000 loop
        --      if Uart1.RX_Ready then
        --          declare
        --              B : Integer := Character'Pos (Uart1.Read_RX);
        --          begin
        --              Uart0.Put ("RX:");
        --              Uart0.Put (Integer'Image (B));
        --              Uart0.Put (" ");
        --          end;
        --      end if;
        --  end loop;

        --  Uart0.Put ("| ");

   end loop;

end Helios;
