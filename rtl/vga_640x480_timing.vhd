-- ============================================================================
-- vga_640x480_timing.vhd
--
-- VGA timing generator ONLY (no color generation)
-- Target mode: 640 x 480 @ 60 Hz (classic VGA)
--
-- Pixel clock: 25 MHz
-- Sync polarity: active-low
--
-- Purpose in project:
--   • Generates correct VGA HSYNC / VSYNC timing
--   • Provides pixel coordinates (x, y)
--   • Provides an "active video" flag
--   • Designed to be reused with a framebuffer-backed renderer
-- ============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity vga_640x480_timing is
  port (
    pixclk_i : in  std_ulogic; -- 25 MHz pixel clock
    rst_i    : in  std_ulogic; -- ACTIVE-HIGH synchronous reset

    hsync_o  : out std_ulogic; -- Horizontal sync (active-low)
    vsync_o  : out std_ulogic; -- Vertical sync (active-low)
    active_o : out std_ulogic; -- '1' when inside visible 640x480 region

    x_o      : out unsigned(9 downto 0); -- Pixel X coordinate (0..639 active)
    y_o      : out unsigned(9 downto 0)  -- Pixel Y coordinate (0..479 active)
  );
end entity;

architecture rtl of vga_640x480_timing is

  -- ============================================================
  -- VGA timing constants (640x480 @ 60 Hz)
  -- ============================================================
  constant H_VISIBLE : integer := 640; -- visible pixels per line
  constant H_FRONT   : integer := 16;  -- front porch
  constant H_SYNC    : integer := 96;  -- HSYNC pulse width
  constant H_BACK    : integer := 48;  -- back porch
  constant H_TOTAL   : integer := 800; -- total pixels per line

  constant V_VISIBLE : integer := 480; -- visible lines per frame
  constant V_FRONT   : integer := 10;  -- front porch
  constant V_SYNC    : integer := 2;   -- VSYNC pulse width
  constant V_BACK    : integer := 33;  -- back porch
  constant V_TOTAL   : integer := 525; -- total lines per frame

  -- ============================================================
  -- Horizontal and vertical pixel counters
  -- ============================================================
  signal h_cnt   : unsigned(9 downto 0) := (others => '0'); -- 0..799
  signal v_cnt   : unsigned(9 downto 0) := (others => '0'); -- 0..524

  -- Internal sync and active flags
  signal hsync_n : std_ulogic := '1'; -- active-low HSYNC
  signal vsync_n : std_ulogic := '1'; -- active-low VSYNC
  signal active  : std_ulogic := '0'; -- active video region flag

begin

  -- ============================================================
  -- Horizontal / Vertical pixel counters
  -- Advances once per pixel clock
  -- ============================================================
  process(pixclk_i)
  begin
    if rising_edge(pixclk_i) then
      if rst_i = '1' then
        -- Reset counters to start of frame
        h_cnt <= (others => '0');
        v_cnt <= (others => '0');
      else
        -- End of line reached?
        if h_cnt = to_unsigned(H_TOTAL - 1, h_cnt'length) then
          h_cnt <= (others => '0');

          -- End of frame reached?
          if v_cnt = to_unsigned(V_TOTAL - 1, v_cnt'length) then
            v_cnt <= (others => '0');
          else
            v_cnt <= v_cnt + 1;
          end if;
        else
          h_cnt <= h_cnt + 1;
        end if;
      end if;
    end if;
  end process;

  -- ============================================================
  -- Combinational logic: sync generation and active region detect
  -- ============================================================
  process(h_cnt, v_cnt)
    variable h_i : integer;
    variable v_i : integer;
  begin
    -- Convert counters to integers for comparisons
    h_i := to_integer(h_cnt);
    v_i := to_integer(v_cnt);

    -- ------------------------------------------------------------
    -- Active video region (640x480)
    -- ------------------------------------------------------------
    if (h_i < H_VISIBLE) and (v_i < V_VISIBLE) then
      active <= '1';
    else
      active <= '0';
    end if;

    -- ------------------------------------------------------------
    -- HSYNC generation (active-low)
    -- ------------------------------------------------------------
    if (h_i >= (H_VISIBLE + H_FRONT)) and
       (h_i <  (H_VISIBLE + H_FRONT + H_SYNC)) then
      hsync_n <= '0';
    else
      hsync_n <= '1';
    end if;

    -- ------------------------------------------------------------
    -- VSYNC generation (active-low)
    -- ------------------------------------------------------------
    if (v_i >= (V_VISIBLE + V_FRONT)) and
       (v_i <  (V_VISIBLE + V_FRONT + V_SYNC)) then
      vsync_n <= '0';
    else
      vsync_n <= '1';
    end if;
  end process;

  -- ============================================================
  -- Output assignments
  -- ============================================================
  hsync_o  <= hsync_n;
  vsync_o  <= vsync_n;
  active_o <= active;

  -- Pixel coordinates (valid during active_o = '1')
  x_o <= h_cnt;
  y_o <= v_cnt;

end architecture;
