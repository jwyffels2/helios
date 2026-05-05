library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Read RGB332 framebuffer bytes from VRAM and present them as a 640x480 VGA
-- stream. Each 160x120 framebuffer pixel is expanded 4x horizontally and 4x
-- vertically, and the color channels are widened from RGB332 to RGB444.
entity vga_scanout_rgb332 is
  generic (
    FB_WIDTH   : positive := 160;
    FB_HEIGHT  : positive := 120;
    PIX_CE_DIV : positive := 4
  );
  port (
    clk_i        : in  std_ulogic;
    rstn_i       : in  std_ulogic;
    vram_addr_o  : out unsigned(14 downto 0);
    vram_rdata_i : in  std_ulogic_vector(7 downto 0);
    vga_hsync_o  : out std_ulogic;
    vga_vsync_o  : out std_ulogic;
    vga_r_o      : out std_ulogic_vector(3 downto 0);
    vga_g_o      : out std_ulogic_vector(3 downto 0);
    vga_b_o      : out std_ulogic_vector(3 downto 0)
  );
end entity;

architecture rtl of vga_scanout_rgb332 is

  signal pix_div_cnt : natural range 0 to PIX_CE_DIV - 1 := 0;
  signal pix_ce      : std_ulogic := '0';

  signal timing_hsync  : std_ulogic;
  signal timing_vsync  : std_ulogic;
  signal timing_active : std_ulogic;
  signal timing_x      : unsigned(9 downto 0);
  signal timing_y      : unsigned(9 downto 0);

  signal hsync_d  : std_ulogic := '1';
  signal vsync_d  : std_ulogic := '1';
  signal active_d : std_ulogic := '0';

  signal red_d   : std_ulogic_vector(3 downto 0) := (others => '0');
  signal green_d : std_ulogic_vector(3 downto 0) := (others => '0');
  signal blue_d  : std_ulogic_vector(3 downto 0) := (others => '0');

  signal fb_x      : unsigned(7 downto 0);
  signal fb_y      : unsigned(6 downto 0);
  signal scan_addr : unsigned(14 downto 0);

begin

  process(clk_i)
  begin
    if rising_edge(clk_i) then
      if rstn_i = '0' then
        pix_div_cnt <= 0;
        pix_ce      <= '0';
      elsif PIX_CE_DIV = 1 then
        pix_div_cnt <= 0;
        pix_ce      <= '1';
      elsif pix_div_cnt = PIX_CE_DIV - 1 then
        pix_div_cnt <= 0;
        pix_ce      <= '1';
      else
        pix_div_cnt <= pix_div_cnt + 1;
        pix_ce      <= '0';
      end if;
    end if;
  end process;

  u_timing : entity work.vga_640x480_timing
    port map (
      clk_i    => clk_i,
      rstn_i   => rstn_i,
      pix_ce_i => pix_ce,
      hsync_o  => timing_hsync,
      vsync_o  => timing_vsync,
      active_o => timing_active,
      x_o      => timing_x,
      y_o      => timing_y
    );

  fb_x <= timing_x(9 downto 2);
  fb_y <= timing_y(8 downto 2);

  scan_addr <= to_unsigned(
                 (to_integer(fb_y) * FB_WIDTH) + to_integer(fb_x),
                 scan_addr'length
               ) when timing_active = '1' else (others => '0');

  vram_addr_o <= scan_addr;

  process(clk_i)
  begin
    if rising_edge(clk_i) then
      if rstn_i = '0' then
        hsync_d  <= '1';
        vsync_d  <= '1';
        active_d <= '0';
        red_d    <= (others => '0');
        green_d  <= (others => '0');
        blue_d   <= (others => '0');
      elsif pix_ce = '1' then
        hsync_d  <= timing_hsync;
        vsync_d  <= timing_vsync;
        active_d <= timing_active;

        red_d   <= vram_rdata_i(7 downto 5) & vram_rdata_i(7);
        green_d <= vram_rdata_i(4 downto 2) & vram_rdata_i(4);
        blue_d  <= vram_rdata_i(1 downto 0) & vram_rdata_i(1 downto 0);
      end if;
    end if;
  end process;

  vga_hsync_o <= hsync_d;
  vga_vsync_o <= vsync_d;
  vga_r_o     <= red_d when active_d = '1' else (others => '0');
  vga_g_o     <= green_d when active_d = '1' else (others => '0');
  vga_b_o     <= blue_d when active_d = '1' else (others => '0');

end architecture;
