library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_vga_scanout_rgb332 is
end entity;

architecture sim of tb_vga_scanout_rgb332 is

   constant Clk_Period : time := 10 ns;
   constant Fb_Size_C  : integer := 160 * 120;

   signal clk_i : std_ulogic := '0';
   signal rstn_i : std_ulogic := '0';
   signal done : boolean := false;

   signal cpu_we_i    : std_ulogic := '0';
   signal cpu_be_i    : std_ulogic_vector(3 downto 0) := (others => '0');
   signal cpu_addr_i  : unsigned(31 downto 0) := (others => '0');
   signal cpu_wdata_i : std_ulogic_vector(31 downto 0) := (others => '0');
   signal cpu_ready_o : std_ulogic;

   signal vram_addr_o  : unsigned(14 downto 0);
   signal vram_rdata_o : std_ulogic_vector(7 downto 0);
   signal vga_hsync_o  : std_ulogic;
   signal vga_vsync_o  : std_ulogic;
   signal vga_r_o      : std_ulogic_vector(3 downto 0);
   signal vga_g_o      : std_ulogic_vector(3 downto 0);
   signal vga_b_o      : std_ulogic_vector(3 downto 0);

begin

   clk_i <= not clk_i after Clk_Period / 2 when not done else '0';

   u_vram : entity work.vram_rgb332_dp
      generic map (
         FB_SIZE => Fb_Size_C
      )
      port map (
         clk_i       => clk_i,
         rstn_i      => rstn_i,
         cpu_we_i    => cpu_we_i,
         cpu_be_i    => cpu_be_i,
         cpu_addr_i  => cpu_addr_i,
         cpu_wdata_i => cpu_wdata_i,
         cpu_ready_o => cpu_ready_o,
         vga_addr_i  => vram_addr_o,
         vga_rdata_o => vram_rdata_o
      );

   u_scanout : entity work.vga_scanout_rgb332
      generic map (
         PIX_CE_DIV => 1
      )
      port map (
         clk_i        => clk_i,
         rstn_i       => rstn_i,
         vram_addr_o  => vram_addr_o,
         vram_rdata_i => vram_rdata_o,
         vga_hsync_o  => vga_hsync_o,
         vga_vsync_o  => vga_vsync_o,
         vga_r_o      => vga_r_o,
         vga_g_o      => vga_g_o,
         vga_b_o      => vga_b_o
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
      cpu_wdata_i <= x"000000E0";
      cpu_we_i    <= '1';
      wait until rising_edge (clk_i);
      cpu_we_i    <= '0';
      cpu_be_i    <= (others => '0');
      cpu_wdata_i <= (others => '0');
      while cpu_ready_o = '0' loop
         wait until rising_edge (clk_i);
      end loop;

      cpu_addr_i  <= to_unsigned (1, cpu_addr_i'length);
      cpu_be_i    <= "0010";
      cpu_wdata_i <= x"00001C00";
      cpu_we_i    <= '1';
      wait until rising_edge (clk_i);
      cpu_we_i    <= '0';
      cpu_be_i    <= (others => '0');
      cpu_wdata_i <= (others => '0');
      while cpu_ready_o = '0' loop
         wait until rising_edge (clk_i);
      end loop;

      for I in 1 to 16 loop
         wait until rising_edge (clk_i);
         exit when (vga_r_o = "1111") and (vga_g_o = "0000") and (vga_b_o = "0000");
      end loop;
      assert (vga_r_o = "1111") and (vga_g_o = "0000") and (vga_b_o = "0000")
         report "Did not observe the first framebuffer pixel on VGA output"
         severity failure;

      for I in 1 to 32 loop
         wait until rising_edge (clk_i);
         exit when vram_addr_o = to_unsigned (4, vram_addr_o'length);
      end loop;
      assert vram_addr_o = to_unsigned (4, vram_addr_o'length)
         report "Scanout address never advanced to framebuffer pixel 4"
         severity failure;

      for I in 1 to 3 loop
         wait until rising_edge (clk_i);
         assert vram_addr_o = to_unsigned (4, vram_addr_o'length)
            report "Framebuffer pixel 4 address was not held for four horizontal scan pixels"
            severity failure;
      end loop;
      wait until rising_edge (clk_i);
      assert vram_addr_o = to_unsigned (5, vram_addr_o'length)
         report "Scanout address did not advance after four horizontal scan pixels"
         severity failure;

      for I in 1 to 700 loop
         wait until rising_edge (clk_i);
         exit when vga_hsync_o = '0';
      end loop;
      assert vga_hsync_o = '0'
         report "HSYNC did not pulse low"
         severity failure;
      assert (vga_r_o = "0000") and (vga_g_o = "0000") and (vga_b_o = "0000")
         report "RGB outputs were not blanked outside the active video region"
         severity failure;

      report "tb_vga_scanout_rgb332 passed" severity note;
      done <= true;
      wait for 2 * Clk_Period;
      wait;
   end process;

end architecture;
