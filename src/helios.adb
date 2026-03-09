with Uart0;         -- Pulls in uart0.ads
with Gnat_Exit;
with min;

procedure Helios is

begin

    -- Initialize uart
    Uart0.Init (19200);

    -- Initialize min
    min.Init;

    -- Send test message
    min.Send_Test;

    -- Loop to prevent program exit
    loop
        Min.Send_Test;
    end loop;

end Helios;
