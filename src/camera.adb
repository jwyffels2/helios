with Uart0;
with Uart1;
with Interfaces; use Interfaces;
with Image_Store; use Image_Store;

package body Camera is

    Chunk_Size : constant Natural := 32;

    Header_0 : constant Byte := 16#76#;
    Header_1 : constant Byte := 16#00#;
    Header_2 : constant Byte := 16#32#;
    Header_3 : constant Byte := 16#00#;
    Header_4 : constant Byte := 16#00#;

    procedure Delay_Loop (Count : Natural) is
    begin
        for I in 1 .. Count loop
            null;
        end loop;
    end Delay_Loop;

    procedure Send_Byte (B : Natural) is
    begin
        while not Uart1.TX_Ready loop
            null;
        end loop;
        Uart1.Write_TX_Byte (Byte (B));
    end Send_Byte;

    procedure Read_Up_To
        (Max_Count     : Natural;
         Timeout_Loops : Natural;
         Buf           : out Byte_Array;
         Count         : out Natural) is
        Waits : Natural := 0;
    begin
        Count := 0;

        while Count < Max_Count loop
            if Uart1.RX_Ready then
                Buf (Count) := Uart1.Read_RX_Byte;
                Count := Count + 1;
                Waits := 0;
            else
                Waits := Waits + 1;
                if Waits > Timeout_Loops then
                    exit;
                end if;
            end if;
        end loop;
    end Read_Up_To;

    procedure Read_Exact
        (Exact_Count   : Natural;
         Timeout_Loops : Natural;
         Buf           : out Byte_Array;
         Success       : out Boolean) is
        Count : Natural := 0;
        Waits : Natural := 0;
    begin
        Success := False;

        while Count < Exact_Count loop
            if Uart1.RX_Ready then
                Buf (Count) := Uart1.Read_RX_Byte;
                Count := Count + 1;
                Waits := 0;
            else
                Waits := Waits + 1;
                if Waits > Timeout_Loops then
                    return;
                end if;
            end if;
        end loop;

        Success := True;
    end Read_Exact;

    procedure Wait_For_Read_FBuf_Header
        (Timeout_Loops : Natural;
         Header_Found  : out Boolean) is
        B     : Byte := 0;
        Waits : Natural := 0;
        State : Natural := 0;
    begin
        Header_Found := False;

        while Waits < Timeout_Loops loop
            if Uart1.RX_Ready then
                B := Uart1.Read_RX_Byte;
                Waits := 0;

                case State is
                    when 0 =>
                        if B = Header_0 then
                            State := 1;
                        end if;

                    when 1 =>
                        if B = Header_1 then
                            State := 2;
                        elsif B = Header_0 then
                            State := 1;
                        else
                            State := 0;
                        end if;

                    when 2 =>
                        if B = Header_2 then
                            State := 3;
                        elsif B = Header_0 then
                            State := 1;
                        else
                            State := 0;
                        end if;

                    when 3 =>
                        if B = Header_3 then
                            State := 4;
                        elsif B = Header_0 then
                            State := 1;
                        else
                            State := 0;
                        end if;

                    when 4 =>
                        if B = Header_4 then
                            Header_Found := True;
                            return;
                        elsif B = Header_0 then
                            State := 1;
                        else
                            State := 0;
                        end if;

                    when others =>
                        State := 0;
                end case;
            else
                Waits := Waits + 1;
            end if;
        end loop;
    end Wait_For_Read_FBuf_Header;

    procedure Send_Stop_Frame is
    begin
        Send_Byte (16#56#);
        Send_Byte (16#00#);
        Send_Byte (16#36#);
        Send_Byte (16#01#);
        Send_Byte (16#00#);
    end Send_Stop_Frame;

    procedure Send_Get_Frame_Length is
    begin
        Send_Byte (16#56#);
        Send_Byte (16#00#);
        Send_Byte (16#34#);
        Send_Byte (16#01#);
        Send_Byte (16#00#);
    end Send_Get_Frame_Length;

    procedure Send_Read_FBuf
        (Address    : Natural;
         Read_Count : Natural) is

        A3 : constant Natural := (Address / 16#1000000#) mod 16#100#;
        A2 : constant Natural := (Address / 16#10000#)   mod 16#100#;
        A1 : constant Natural := (Address / 16#100#)     mod 16#100#;
        A0 : constant Natural :=  Address                 mod 16#100#;

        C3 : constant Natural := (Read_Count / 16#1000000#) mod 16#100#;
        C2 : constant Natural := (Read_Count / 16#10000#)   mod 16#100#;
        C1 : constant Natural := (Read_Count / 16#100#)     mod 16#100#;
        C0 : constant Natural :=  Read_Count                 mod 16#100#;
    begin
        Send_Byte (16#56#);
        Send_Byte (16#00#);
        Send_Byte (16#32#);
        Send_Byte (16#0C#);
        Send_Byte (16#00#);
        Send_Byte (16#0A#);

        Send_Byte (A3);
        Send_Byte (A2);
        Send_Byte (A1);
        Send_Byte (A0);

        Send_Byte (C3);
        Send_Byte (C2);
        Send_Byte (C1);
        Send_Byte (C0);

        Send_Byte (16#00#);
        Send_Byte (16#20#);
    end Send_Read_FBuf;

    procedure Init is
    begin
        Uart1.Init (38400);
        Delay_Loop (10_000_000);
        Uart1.Flush_RX;
    end Init;

    procedure Capture_Image (Img_Len : out Natural; Success : out Boolean) is
        Stop_Buf   : Byte_Array (0 .. 4);
        Len_Buf    : Byte_Array (0 .. 8);
        Data_Buf   : Byte_Array (0 .. Chunk_Size - 1);
        Footer_Buf : Byte_Array (0 .. 4);

        Count        : Natural := 0;
        Total_Chunks : Natural := 0;
        Bytes_Read   : Natural := 0;

        Header_Found : Boolean := False;
        Data_OK      : Boolean := False;
        Footer_OK    : Boolean := False;
    begin
        Success := False;
        Img_Len := 0;

        Send_Stop_Frame;
        Read_Up_To (5, 20_000_000, Stop_Buf, Count);

        if Count /= 5 then
            return;
        end if;

        Delay_Loop (2_000_000);
        Uart1.Flush_RX;

        Send_Get_Frame_Length;
        Read_Up_To (9, 30_000_000, Len_Buf, Count);

        if Count /= 9 then
            return;
        end if;

        Img_Len :=
            Natural (Len_Buf (5)) * 16#1000000# +
            Natural (Len_Buf (6)) * 16#10000# +
            Natural (Len_Buf (7)) * 16#100# +
            Natural (Len_Buf (8));

        if Img_Len = 0 then
            return;
        end if;

        if Img_Len > Max_Image_Size then
            return;
        end if;

        Total_Chunks := (Img_Len + Chunk_Size - 1) / Chunk_Size;

        Delay_Loop (2_000_000);

        for Chunk in 0 .. Total_Chunks - 1 loop
            declare
                Start_Addr : constant Natural := Chunk * Chunk_Size;
                Remaining  : constant Natural := Img_Len - Start_Addr;
                This_Read  : constant Natural :=
                    (if Remaining > Chunk_Size then Chunk_Size else Remaining);
            begin
                Send_Read_FBuf (Start_Addr, This_Read);

                Wait_For_Read_FBuf_Header (50_000_000, Header_Found);
                if not Header_Found then
                    return;
                end if;

                Read_Exact (This_Read, 50_000_000, Data_Buf, Data_OK);
                if not Data_OK then
                    return;
                end if;

                Read_Exact (5, 50_000_000, Footer_Buf, Footer_OK);
                if not Footer_OK then
                    return;
                end if;

                if Footer_Buf (0) /= Header_0 or else
                   Footer_Buf (1) /= Header_1 or else
                   Footer_Buf (2) /= Header_2 or else
                   Footer_Buf (3) /= Header_3 or else
                   Footer_Buf (4) /= Header_4
                then
                    return;
                end if;

                for I in 0 .. This_Read - 1 loop
                    Image_Buf (Start_Addr + I) := Data_Buf (I);
                end loop;

                Bytes_Read := Bytes_Read + This_Read;
                Delay_Loop (500_000);
            end;
        end loop;

        Success := (Bytes_Read = Img_Len);

    end Capture_Image;

end Camera;
