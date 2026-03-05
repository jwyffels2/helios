library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_vram_rgb332_dp is
end entity;

architecture sim of tb_vram_rgb332_dp is

   constant Clk_Period : time := 10 ns;
   constant Fb_Size_C  : integer := 64;

   signal clk_i : std_ulogic := '0';
   signal rstn_i : std_ulogic := '0';
   signal done : boolean := false;

   signal cpu_we_i    : std_ulogic := '0';
   signal cpu_be_i    : std_ulogic_vector(3 downto 0) := (others => '0');
   signal cpu_addr_i  : unsigned(31 downto 0) := (others => '0');
   signal cpu_wdata_i : std_ulogic_vector(31 downto 0) := (others => '0');
   signal cpu_ready_o : std_ulogic;

   signal vga_addr_i  : unsigned(14 downto 0) := (others => '0');
   signal vga_rdata_o : std_ulogic_vector(7 downto 0);

begin

   clk_i <= not clk_i after Clk_Period / 2 when not done else '0';

   dut : entity work.vram_rgb332_dp
      generic map (
         FB_SIZE => Fb_Size_C
      )
      port map (
         clk_i => clk_i,
         rstn_i => rstn_i,
         cpu_we_i => cpu_we_i,
         cpu_be_i => cpu_be_i,
         cpu_addr_i => cpu_addr_i,
         cpu_wdata_i => cpu_wdata_i,
         cpu_ready_o => cpu_ready_o,
         vga_addr_i => vga_addr_i,
         vga_rdata_o => vga_rdata_o
      );

   stimulus : process
   begin
      for I in 1 to 3 loop
         wait until rising_edge (clk_i);
      end loop;
      rstn_i <= '1';
      for I in 1 to 2 loop
         wait until rising_edge (clk_i);
      end loop;

      assert cpu_ready_o = '1'
         report "VRAM not ready after reset"
         severity failure;

      cpu_addr_i  <= to_unsigned (0, cpu_addr_i'length);
      cpu_be_i    <= "0001";
      cpu_wdata_i <= x"000000AA";
      cpu_we_i    <= '1';
      wait until rising_edge (clk_i);
      cpu_we_i    <= '0';
      cpu_be_i    <= (others => '0');
      cpu_wdata_i <= (others => '0');
      while cpu_ready_o = '0' loop
         wait until rising_edge (clk_i);
      end loop;
      vga_addr_i <= to_unsigned (0, vga_addr_i'length);
      for I in 1 to 8 loop
         wait until rising_edge (clk_i);
         exit when vga_rdata_o = x"AA";
      end loop;
      assert vga_rdata_o = x"AA"
         report "Lane 0 byte write failed"
         severity failure;

      cpu_addr_i  <= to_unsigned (1, cpu_addr_i'length);
      cpu_be_i    <= "0010";
      cpu_wdata_i <= x"0000BB00";
      cpu_we_i    <= '1';
      wait until rising_edge (clk_i);
      cpu_we_i    <= '0';
      cpu_be_i    <= (others => '0');
      cpu_wdata_i <= (others => '0');
      while cpu_ready_o = '0' loop
         wait until rising_edge (clk_i);
      end loop;
      vga_addr_i <= to_unsigned (1, vga_addr_i'length);
      for I in 1 to 8 loop
         wait until rising_edge (clk_i);
         exit when vga_rdata_o = x"BB";
      end loop;
      assert vga_rdata_o = x"BB"
         report "Lane 1 byte write failed"
         severity failure;

      cpu_addr_i  <= to_unsigned (4, cpu_addr_i'length);
      cpu_be_i    <= "1111";
      cpu_wdata_i <= x"11223344";
      cpu_we_i    <= '1';
      wait until rising_edge (clk_i);
      cpu_we_i    <= '0';
      cpu_be_i    <= (others => '0');
      cpu_wdata_i <= (others => '0');
      while cpu_ready_o = '0' loop
         wait until rising_edge (clk_i);
      end loop;

      vga_addr_i <= to_unsigned (4, vga_addr_i'length);
      for I in 1 to 8 loop
         wait until rising_edge (clk_i);
         exit when vga_rdata_o = x"44";
      end loop;
      assert vga_rdata_o = x"44"
         report "Word write byte 0 mismatch"
         severity failure;

      vga_addr_i <= to_unsigned (5, vga_addr_i'length);
      for I in 1 to 8 loop
         wait until rising_edge (clk_i);
         exit when vga_rdata_o = x"33";
      end loop;
      assert vga_rdata_o = x"33"
         report "Word write byte 1 mismatch"
         severity failure;

      vga_addr_i <= to_unsigned (6, vga_addr_i'length);
      for I in 1 to 8 loop
         wait until rising_edge (clk_i);
         exit when vga_rdata_o = x"22";
      end loop;
      assert vga_rdata_o = x"22"
         report "Word write byte 2 mismatch"
         severity failure;

      vga_addr_i <= to_unsigned (7, vga_addr_i'length);
      for I in 1 to 8 loop
         wait until rising_edge (clk_i);
         exit when vga_rdata_o = x"11";
      end loop;
      assert vga_rdata_o = x"11"
         report "Word write byte 3 mismatch"
         severity failure;

      report "tb_vram_rgb332_dp passed" severity note;
      done <= true;
      wait for 2 * Clk_Period;
      wait;
   end process;

end architecture;
