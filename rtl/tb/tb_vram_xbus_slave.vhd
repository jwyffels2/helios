library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_vram_xbus_slave is
end entity;

architecture sim of tb_vram_xbus_slave is

   constant Clk_Period  : time := 10 ns;
   constant Fb_Size_C   : integer := 64;
   constant Base_Addr_C : unsigned(31 downto 0) := x"F0000000";
   constant Win_Size_C  : unsigned(31 downto 0) := x"00000040";

   signal clk_i : std_ulogic := '0';
   signal rstn_i : std_ulogic := '0';
   signal done : boolean := false;

   signal xbus_cyc_i : std_ulogic := '0';
   signal xbus_stb_i : std_ulogic := '0';
   signal xbus_we_i  : std_ulogic := '0';
   signal xbus_adr_i : std_ulogic_vector(31 downto 0) := (others => '0');
   signal xbus_dat_i : std_ulogic_vector(31 downto 0) := (others => '0');
   signal xbus_sel_i : std_ulogic_vector(3 downto 0) := (others => '0');

   signal xbus_ack_o : std_ulogic;
   signal xbus_dat_o : std_ulogic_vector(31 downto 0);

   signal cpu_we : std_ulogic;
   signal cpu_be : std_ulogic_vector(3 downto 0);
   signal cpu_addr : unsigned(31 downto 0);
   signal cpu_wdata : std_ulogic_vector(31 downto 0);
   signal vram_ready : std_ulogic;

   signal vga_addr_i  : unsigned(14 downto 0) := (others => '0');
   signal vga_rdata_o : std_ulogic_vector(7 downto 0);

begin

   clk_i <= not clk_i after Clk_Period / 2 when not done else '0';

   u_xbus : entity work.vram_xbus_slave
      generic map (
         BASE_ADDR => Base_Addr_C,
         WIN_SIZE  => Win_Size_C
      )
      port map (
         clk_i => clk_i,
         rstn_i => rstn_i,
         xbus_cyc_i => xbus_cyc_i,
         xbus_stb_i => xbus_stb_i,
         xbus_we_i => xbus_we_i,
         xbus_adr_i => xbus_adr_i,
         xbus_dat_i => xbus_dat_i,
         xbus_sel_i => xbus_sel_i,
         xbus_ack_o => xbus_ack_o,
         xbus_dat_o => xbus_dat_o,
         vram_ready_i => vram_ready,
         cpu_we_o => cpu_we,
         cpu_be_o => cpu_be,
         cpu_addr_o => cpu_addr,
         cpu_wdata_o => cpu_wdata
      );

   u_vram : entity work.vram_rgb332_dp
      generic map (
         FB_SIZE => Fb_Size_C
      )
      port map (
         clk_i => clk_i,
         rstn_i => rstn_i,
         cpu_we_i => cpu_we,
         cpu_be_i => cpu_be,
         cpu_addr_i => cpu_addr,
         cpu_wdata_i => cpu_wdata,
         cpu_ready_o => vram_ready,
         vga_addr_i => vga_addr_i,
         vga_rdata_o => vga_rdata_o
      );

   stimulus : process
      variable Ack_Seen : boolean;
   begin
      for I in 1 to 3 loop
         wait until rising_edge (clk_i);
      end loop;
      rstn_i <= '1';
      for I in 1 to 2 loop
         wait until rising_edge (clk_i);
      end loop;

      xbus_adr_i <= std_ulogic_vector (Base_Addr_C + to_unsigned (0, 32));
      xbus_dat_i <= x"000000AB";
      xbus_sel_i <= "0001";
      xbus_we_i  <= '1';
      xbus_cyc_i <= '1';
      xbus_stb_i <= '1';
      wait until rising_edge (clk_i);
      Ack_Seen := (xbus_ack_o = '1');
      for I in 1 to 20 loop
         exit when Ack_Seen;
         wait until rising_edge (clk_i);
         Ack_Seen := (xbus_ack_o = '1');
      end loop;
      assert Ack_Seen report "XBUS lane0 write ack timeout" severity failure;
      xbus_cyc_i <= '0';
      xbus_stb_i <= '0';
      xbus_we_i  <= '0';
      xbus_sel_i <= (others => '0');
      xbus_dat_i <= (others => '0');
      wait until rising_edge (clk_i);
      vga_addr_i <= to_unsigned (0, vga_addr_i'length);
      for I in 1 to 8 loop
         wait until rising_edge (clk_i);
         exit when vga_rdata_o = x"AB";
      end loop;
      assert vga_rdata_o = x"AB"
         report "XBUS lane0 write data mismatch"
         severity failure;

      xbus_adr_i <= std_ulogic_vector (Base_Addr_C + to_unsigned (1, 32));
      xbus_dat_i <= x"0000CD00";
      xbus_sel_i <= "0010";
      xbus_we_i  <= '1';
      xbus_cyc_i <= '1';
      xbus_stb_i <= '1';
      wait until rising_edge (clk_i);
      xbus_stb_i <= '0';
      Ack_Seen := (xbus_ack_o = '1');
      for I in 1 to 20 loop
         exit when Ack_Seen;
         wait until rising_edge (clk_i);
         Ack_Seen := (xbus_ack_o = '1');
      end loop;
      assert Ack_Seen report "XBUS dropped-STB write ack timeout" severity failure;
      xbus_cyc_i <= '0';
      xbus_we_i  <= '0';
      xbus_sel_i <= (others => '0');
      xbus_dat_i <= (others => '0');
      wait until rising_edge (clk_i);
      vga_addr_i <= to_unsigned (1, vga_addr_i'length);
      for I in 1 to 8 loop
         wait until rising_edge (clk_i);
         exit when vga_rdata_o = x"CD";
      end loop;
      assert vga_rdata_o = x"CD"
         report "XBUS dropped-STB write data mismatch"
         severity failure;

      xbus_adr_i <= std_ulogic_vector (Base_Addr_C + to_unsigned (4, 32));
      xbus_dat_i <= x"11223344";
      xbus_sel_i <= "1111";
      xbus_we_i  <= '1';
      xbus_cyc_i <= '1';
      xbus_stb_i <= '1';
      wait until rising_edge (clk_i);
      Ack_Seen := (xbus_ack_o = '1');
      for I in 1 to 20 loop
         exit when Ack_Seen;
         wait until rising_edge (clk_i);
         Ack_Seen := (xbus_ack_o = '1');
      end loop;
      assert Ack_Seen report "XBUS word write ack timeout" severity failure;
      xbus_cyc_i <= '0';
      xbus_stb_i <= '0';
      xbus_we_i  <= '0';
      xbus_sel_i <= (others => '0');
      xbus_dat_i <= (others => '0');
      wait until rising_edge (clk_i);
      vga_addr_i <= to_unsigned (4, vga_addr_i'length);
      for I in 1 to 8 loop
         wait until rising_edge (clk_i);
         exit when vga_rdata_o = x"44";
      end loop;
      assert vga_rdata_o = x"44"
         report "XBUS word write byte 0 mismatch"
         severity failure;
      vga_addr_i <= to_unsigned (5, vga_addr_i'length);
      for I in 1 to 8 loop
         wait until rising_edge (clk_i);
         exit when vga_rdata_o = x"33";
      end loop;
      assert vga_rdata_o = x"33"
         report "XBUS word write byte 1 mismatch"
         severity failure;
      vga_addr_i <= to_unsigned (6, vga_addr_i'length);
      for I in 1 to 8 loop
         wait until rising_edge (clk_i);
         exit when vga_rdata_o = x"22";
      end loop;
      assert vga_rdata_o = x"22"
         report "XBUS word write byte 2 mismatch"
         severity failure;
      vga_addr_i <= to_unsigned (7, vga_addr_i'length);
      for I in 1 to 8 loop
         wait until rising_edge (clk_i);
         exit when vga_rdata_o = x"11";
      end loop;
      assert vga_rdata_o = x"11"
         report "XBUS word write byte 3 mismatch"
         severity failure;

      xbus_adr_i <= std_ulogic_vector (Base_Addr_C + to_unsigned (8, 32));
      xbus_dat_i <= x"A1B2C3D4";
      xbus_sel_i <= "1111";
      xbus_we_i  <= '1';
      xbus_cyc_i <= '1';
      xbus_stb_i <= '1';
      wait until rising_edge (clk_i);
      Ack_Seen := (xbus_ack_o = '1');
      for I in 1 to 20 loop
         exit when Ack_Seen;
         wait until rising_edge (clk_i);
         Ack_Seen := (xbus_ack_o = '1');
      end loop;
      assert Ack_Seen report "XBUS seed write ack timeout" severity failure;
      xbus_cyc_i <= '0';
      xbus_stb_i <= '0';
      xbus_we_i  <= '0';
      xbus_sel_i <= (others => '0');
      xbus_dat_i <= (others => '0');
      wait until rising_edge (clk_i);

      vga_addr_i <= to_unsigned (8, vga_addr_i'length);
      for I in 1 to 8 loop
         wait until rising_edge (clk_i);
         exit when vga_rdata_o = x"D4";
      end loop;
      assert vga_rdata_o = x"D4"
         report "XBUS seed write byte 0 mismatch"
         severity failure;
      vga_addr_i <= to_unsigned (9, vga_addr_i'length);
      for I in 1 to 8 loop
         wait until rising_edge (clk_i);
         exit when vga_rdata_o = x"C3";
      end loop;
      assert vga_rdata_o = x"C3"
         report "XBUS seed write byte 1 mismatch"
         severity failure;
      vga_addr_i <= to_unsigned (10, vga_addr_i'length);
      for I in 1 to 8 loop
         wait until rising_edge (clk_i);
         exit when vga_rdata_o = x"B2";
      end loop;
      assert vga_rdata_o = x"B2"
         report "XBUS seed write byte 2 mismatch"
         severity failure;
      vga_addr_i <= to_unsigned (11, vga_addr_i'length);
      for I in 1 to 8 loop
         wait until rising_edge (clk_i);
         exit when vga_rdata_o = x"A1";
      end loop;
      assert vga_rdata_o = x"A1"
         report "XBUS seed write byte 3 mismatch"
         severity failure;

      xbus_adr_i <= std_ulogic_vector (Base_Addr_C + to_unsigned (8, 32));
      xbus_dat_i <= x"55667788";
      xbus_sel_i <= "0000";
      xbus_we_i  <= '1';
      xbus_cyc_i <= '1';
      xbus_stb_i <= '1';
      wait until rising_edge (clk_i);
      Ack_Seen := (xbus_ack_o = '1');
      for I in 1 to 20 loop
         exit when Ack_Seen;
         wait until rising_edge (clk_i);
         Ack_Seen := (xbus_ack_o = '1');
      end loop;
      assert Ack_Seen report "XBUS zero-select write ack timeout" severity failure;
      xbus_cyc_i <= '0';
      xbus_stb_i <= '0';
      xbus_we_i  <= '0';
      xbus_sel_i <= (others => '0');
      xbus_dat_i <= (others => '0');
      wait until rising_edge (clk_i);

      vga_addr_i <= to_unsigned (8, vga_addr_i'length);
      for I in 1 to 8 loop
         wait until rising_edge (clk_i);
         exit when vga_rdata_o = x"D4";
      end loop;
      assert vga_rdata_o = x"D4"
         report "XBUS zero-select write changed byte 0"
         severity failure;
      vga_addr_i <= to_unsigned (9, vga_addr_i'length);
      for I in 1 to 8 loop
         wait until rising_edge (clk_i);
         exit when vga_rdata_o = x"C3";
      end loop;
      assert vga_rdata_o = x"C3"
         report "XBUS zero-select write changed byte 1"
         severity failure;
      vga_addr_i <= to_unsigned (10, vga_addr_i'length);
      for I in 1 to 8 loop
         wait until rising_edge (clk_i);
         exit when vga_rdata_o = x"B2";
      end loop;
      assert vga_rdata_o = x"B2"
         report "XBUS zero-select write changed byte 2"
         severity failure;
      vga_addr_i <= to_unsigned (11, vga_addr_i'length);
      for I in 1 to 8 loop
         wait until rising_edge (clk_i);
         exit when vga_rdata_o = x"A1";
      end loop;
      assert vga_rdata_o = x"A1"
         report "XBUS zero-select write changed byte 3"
         severity failure;

      xbus_adr_i <= std_ulogic_vector (Base_Addr_C + to_unsigned (0, 32));
      xbus_we_i  <= '0';
      xbus_cyc_i <= '1';
      xbus_stb_i <= '1';
      wait until rising_edge (clk_i);
      Ack_Seen := (xbus_ack_o = '1');
      for I in 1 to 20 loop
         exit when Ack_Seen;
         wait until rising_edge (clk_i);
         Ack_Seen := (xbus_ack_o = '1');
      end loop;
      assert Ack_Seen report "XBUS read ack timeout" severity failure;
      assert xbus_dat_o = (xbus_dat_o'range => '0')
         report "XBUS read should return zeros"
         severity failure;
      xbus_cyc_i <= '0';
      xbus_stb_i <= '0';
      wait until rising_edge (clk_i);

      xbus_adr_i <= std_ulogic_vector (Base_Addr_C + x"00000100");
      xbus_dat_i <= x"FFFFFFFF";
      xbus_sel_i <= "1111";
      xbus_we_i  <= '1';
      xbus_cyc_i <= '1';
      xbus_stb_i <= '1';
      wait until rising_edge (clk_i);
      for I in 1 to 5 loop
         wait until rising_edge (clk_i);
         assert xbus_ack_o = '0'
            report "Out-of-range access should not be acknowledged"
            severity failure;
      end loop;
      xbus_cyc_i <= '0';
      xbus_stb_i <= '0';
      xbus_we_i  <= '0';
      xbus_sel_i <= (others => '0');
      xbus_dat_i <= (others => '0');
      wait until rising_edge (clk_i);

      report "tb_vram_xbus_slave passed" severity note;
      done <= true;
      wait for 2 * Clk_Period;
      wait;
   end process;

end architecture;
