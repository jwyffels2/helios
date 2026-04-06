with Uart0;         -- Pulls in uart0.ads
with Uart1;
with Gnat_Exit;
with min;
with Interfaces.C; use Interfaces.C;

procedure Helios is


begin

    -- Initialize uart0
    Uart0.Init (19200);

    -- Initialize uart1
    Uart1.Init (38400);


    Uart0.Put ("sending 1 : ");
    while not Uart1.TX_Ready loop
        null;
    end loop;
    Uart1.Write_TX (Character'Val (16#56#));

    Uart0.Put ("sending 2 : ");
    while not Uart1.TX_Ready loop
        null;
    end loop;
    Uart1.Write_TX (Character'Val (16#00#));

    Uart0.Put ("sending 3 : ");
    while not Uart1.TX_Ready loop
        null;
    end loop;
    Uart1.Write_TX (Character'Val (16#11#));

    Uart0.Put ("sending 4 : ");
    while not Uart1.TX_Ready loop
        null;
    end loop;
    Uart1.Write_TX (Character'Val (16#01#));

    Uart0.Put ("waiting : ");
    loop
        if Uart1.RX_Ready then
            declare
                B : Interfaces.Unsigned_8 := Interfaces.Unsigned_8 (Character'Pos (Uart1.Read_RX));
            begin
                -- print byte to UART0
                Uart0.Put("RX: ");
                Uart0.Put(Integer'Image(Integer(B)));
                Uart0.Put(" ");
            end;
        end if;
    end loop;

    Uart0.Put ("  EOP  ");

end Helios;
