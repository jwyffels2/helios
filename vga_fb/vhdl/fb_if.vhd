library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- ============================================================================
-- fb_if
-- ============================================================================
-- Framebuffer interface block intended to be instantiated from rtl/helios.vhdl.
--
-- What this block does:
--   - Exposes a Wishbone-like (NEORV32 XBUS compatible) write interface
--     to a byte-addressed RGB332 framebuffer (160x120 -> 19200 bytes).
--   - Provides a simple VGA scanout read path: given 640x480 timing X/Y and
--     ACTIVE, it reads the corresponding framebuffer byte.
--
-- Notes:
--   - VRAM read has 1-cycle latency (registered output). Therefore
--     vga_active_o is a 1-cycle delayed version of vga_active_i and is
--     aligned with vga_pixel_o.
--   - Address mapping is row-major: addr = (fb_y * 160) + fb_x, 1 byte/pixel.
--   - 640x480 -> 160x120 is done via a fixed 4x downscale (x>>2, y>>2).
-- ============================================================================

entity fb_if is
  generic (
    BASE_ADDR : unsigned(31 downto 0) := x"F0000000";
    WIN_SIZE  : unsigned(31 downto 0) := x"00005000"; -- 20,480 bytes
    FB_SIZE   : integer := 19200
  );
  port (
    clk_i  : in  std_ulogic;
    rstn_i : in  std_ulogic; -- active-low reset

    -- Wishbone-like slave interface (NEORV32 XBUS compatible)
    wb_cyc_i : in  std_ulogic;
    wb_stb_i : in  std_ulogic;
    wb_we_i  : in  std_ulogic;
    wb_adr_i : in  std_ulogic_vector(31 downto 0);
    wb_dat_i : in  std_ulogic_vector(31 downto 0);
    wb_sel_i : in  std_ulogic_vector(3 downto 0);

    wb_ack_o : out std_ulogic;
    wb_dat_o : out std_ulogic_vector(31 downto 0);

    -- VGA scanout side (from 640x480 timing generator)
    vga_x_i      : in  unsigned(9 downto 0); -- 0..799
    vga_y_i      : in  unsigned(9 downto 0); -- 0..524
    vga_active_i : in  std_ulogic;           -- '1' for 640x480 visible area

    vga_pixel_o  : out std_ulogic_vector(7 downto 0); -- RGB332
    vga_active_o : out std_ulogic                     -- delayed 1 cycle, aligned to vga_pixel_o
  );
end entity;

architecture rtl of fb_if is

  -- VRAM write-side interface (from bus slave to VRAM)
  signal cpu_we    : std_ulogic;
  signal cpu_be    : std_ulogic_vector(3 downto 0);
  signal cpu_addr  : unsigned(31 downto 0);
  signal cpu_wdata : std_ulogic_vector(31 downto 0);
  signal vram_ready: std_ulogic;

  -- VRAM scanout interface
  signal vga_addr  : unsigned(14 downto 0) := (others => '0');
  signal vga_rdata : std_ulogic_vector(7 downto 0) := (others => '0');
  signal active_d  : std_ulogic := '0';

begin

  -- ------------------------------------------------------------
  -- Bus slave -> VRAM write interface
  -- ------------------------------------------------------------
  u_wb : entity work.vram_wb_slave
    generic map (
      BASE_ADDR => BASE_ADDR,
      WIN_SIZE  => WIN_SIZE
    )
    port map (
      clk_i => clk_i,
      rstn_i => rstn_i,

      wb_cyc_i => wb_cyc_i,
      wb_stb_i => wb_stb_i,
      wb_we_i  => wb_we_i,
      wb_adr_i => wb_adr_i,
      wb_dat_i => wb_dat_i,
      wb_sel_i => wb_sel_i,

      wb_ack_o => wb_ack_o,
      wb_dat_o => wb_dat_o,

      vram_ready_i => vram_ready,
      cpu_we_o     => cpu_we,
      cpu_be_o     => cpu_be,
      cpu_addr_o   => cpu_addr,
      cpu_wdata_o  => cpu_wdata
    );

  -- ------------------------------------------------------------
  -- VRAM block
  -- ------------------------------------------------------------
  u_vram : entity work.vram_rgb332_dp
    generic map (
      FB_SIZE => FB_SIZE
    )
    port map (
      clk_i => clk_i,
      rstn_i => rstn_i,

      cpu_we_i    => cpu_we,
      cpu_be_i    => cpu_be,
      cpu_addr_i  => cpu_addr,
      cpu_wdata_i => cpu_wdata,
      cpu_ready_o => vram_ready,

      vga_addr_i  => vga_addr,
      vga_rdata_o => vga_rdata
    );

  -- ------------------------------------------------------------
  -- VGA scanout address mapping (640x480 -> 160x120, 4x downscale)
  --
  -- addr = (y>>2) * 160 + (x>>2)
  -- 160 = 128 + 32 => (y<<7) + (y<<5)
  -- ------------------------------------------------------------
  process(vga_x_i, vga_y_i, vga_active_i)
    variable fb_x   : unsigned(7 downto 0);
    variable fb_y   : unsigned(7 downto 0);
    variable y_base : unsigned(14 downto 0);
    variable addr_v : unsigned(14 downto 0);
  begin
    if vga_active_i = '1' then
      fb_x := vga_x_i(9 downto 2);
      fb_y := vga_y_i(9 downto 2);

      y_base := shift_left(resize(fb_y, 15), 7) + shift_left(resize(fb_y, 15), 5);
      addr_v := y_base + resize(fb_x, 15);

      vga_addr <= addr_v;
    else
      vga_addr <= (others => '0');
    end if;
  end process;

  -- Align active with the 1-cycle VRAM read latency
  process(clk_i)
  begin
    if rising_edge(clk_i) then
      if rstn_i = '0' then
        active_d <= '0';
      else
        active_d <= vga_active_i;
      end if;
    end if;
  end process;

  vga_active_o <= active_d;
  vga_pixel_o  <= vga_rdata when active_d = '1' else (others => '0');

end architecture;
