with Uart0;
with Gnat_Exit;
with min;

procedure Helios is

    procedure Custom_Delay is
    begin
        for I in 1 .. 10_000_000 loop
            null;
        end loop;
    end Custom_Delay;

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
        Custom_Delay;
    end loop;

end Helios;
