-- ============================================================================
-- vga_640x480_safe.vhd
--
-- Safe, self-contained VGA timing + test-pattern generator
-- Target mode: 640 x 480 @ 60 Hz (classic VGA)
--
-- Pixel clock: 25 MHz
-- Sync polarity: active-low (standard VGA)
--
-- Purpose in project:
--   • Provides known-good VGA timing
--   • Generates a visible test pattern (vertical color bars)
--   • Used as a baseline before integrating framebuffer-backed rendering
-- ============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity vga_640x480_safe is
  port (
    pixclk_i : in  std_ulogic; -- 25 MHz pixel clock
    rst_i    : in  std_ulogic; -- ACTIVE-HIGH synchronous reset

    hsync_o  : out std_ulogic; -- Horizontal sync (active-low)
    vsync_o  : out std_ulogic; -- Vertical sync (active-low)
    r_o      : out std_ulogic_vector(3 downto 0); -- Red   (4-bit DAC)
    g_o      : out std_ulogic_vector(3 downto 0); -- Green (4-bit DAC)
    b_o      : out std_ulogic_vector(3 downto 0)  -- Blue  (4-bit DAC)
  );
end entity;

architecture rtl of vga_640x480_safe is

  -- ============================================================
  -- VGA timing constants (640x480 @ 60 Hz)
  -- ============================================================
  constant H_VISIBLE : integer := 640; -- visible pixels per line
  constant H_FRONT   : integer := 16;  -- front porch
  constant H_SYNC    : integer := 96;  -- sync pulse width
  constant H_BACK    : integer := 48;  -- back porch
  constant H_TOTAL   : integer := 800; -- total pixels per line

  constant V_VISIBLE : integer := 480; -- visible lines per frame
  constant V_FRONT   : integer := 10;
  constant V_SYNC    : integer := 2;
  constant V_BACK    : integer := 33;
  constant V_TOTAL   : integer := 525; -- total lines per frame

  -- ============================================================
  -- Horizontal and vertical pixel counters
  -- ============================================================
  signal h_cnt : unsigned(9 downto 0) := (others => '0'); -- 0..799
  signal v_cnt : unsigned(9 downto 0) := (others => '0'); -- 0..524

  -- ============================================================
  -- Registered output signals
  -- Registering outputs improves timing cleanliness
  -- ============================================================
  signal hsync_r : std_ulogic := '1'; -- active-low
  signal vsync_r : std_ulogic := '1'; -- active-low
  signal r_r     : std_ulogic_vector(3 downto 0) := (others => '0');
  signal g_r     : std_ulogic_vector(3 downto 0) := (others => '0');
  signal b_r     : std_ulogic_vector(3 downto 0) := (others => '0');

begin

  -- ============================================================
  -- Main pixel clocked process
  --
  -- Handles:
  --   • Horizontal and vertical counters
  --   • Sync pulse generation
  --   • Active video detection
  --   • Test pattern generation
  -- ============================================================
  process(pixclk_i)
    variable h_i  : integer;
    variable v_i  : integer;
    variable x    : integer;
    variable bar  : integer;
    variable act  : boolean;
  begin
    if rising_edge(pixclk_i) then
      if rst_i = '1' then
        -- Reset all state
        h_cnt   <= (others => '0');
        v_cnt   <= (others => '0');
        hsync_r <= '1';
        vsync_r <= '1';
        r_r     <= (others => '0');
        g_r     <= (others => '0');
        b_r     <= (others => '0');
      else
        -- --------------------------------------------------------
        -- Horizontal / Vertical counters
        -- --------------------------------------------------------
        if h_cnt = to_unsigned(H_TOTAL - 1, h_cnt'length) then
          h_cnt <= (others => '0');
          if v_cnt = to_unsigned(V_TOTAL - 1, v_cnt'length) then
            v_cnt <= (others => '0');
          else
            v_cnt <= v_cnt + 1;
          end if;
        else
          h_cnt <= h_cnt + 1;
        end if;

        -- Convert counters to integers for comparisons
        h_i := to_integer(h_cnt);
        v_i := to_integer(v_cnt);

        -- --------------------------------------------------------
        -- Active video region detection
        -- --------------------------------------------------------
        act := (h_i < H_VISIBLE) and (v_i < V_VISIBLE);

        -- --------------------------------------------------------
        -- HSYNC generation (active-low)
        -- --------------------------------------------------------
        if (h_i >= (H_VISIBLE + H_FRONT)) and
           (h_i <  (H_VISIBLE + H_FRONT + H_SYNC)) then
          hsync_r <= '0';
        else
          hsync_r <= '1';
        end if;

        -- --------------------------------------------------------
        -- VSYNC generation (active-low)
        -- --------------------------------------------------------
        if (v_i >= (V_VISIBLE + V_FRONT)) and
           (v_i <  (V_VISIBLE + V_FRONT + V_SYNC)) then
          vsync_r <= '0';
        else
          vsync_r <= '1';
        end if;

        -- --------------------------------------------------------
        -- Test pattern: 8 vertical color bars
        -- --------------------------------------------------------
        if not act then
          -- Outside visible region → black
          r_r <= (others => '0');
          g_r <= (others => '0');
          b_r <= (others => '0');
        else
          x   := h_i;    -- pixel column (0..639)
          bar := x / 80; -- divide screen into 8 bars

          case bar is
            when 0 => r_r <= "1111"; g_r <= "0000"; b_r <= "0000"; -- red
            when 1 => r_r <= "1111"; g_r <= "1111"; b_r <= "0000"; -- yellow
            when 2 => r_r <= "0000"; g_r <= "1111"; b_r <= "0000"; -- green
            when 3 => r_r <= "0000"; g_r <= "1111"; b_r <= "1111"; -- cyan
            when 4 => r_r <= "0000"; g_r <= "0000"; b_r <= "1111"; -- blue
            when 5 => r_r <= "1111"; g_r <= "0000"; b_r <= "1111"; -- magenta
            when 6 => r_r <= "1111"; g_r <= "1111"; b_r <= "1111"; -- white
            when others =>
              r_r <= "0010"; g_r <= "0010"; b_r <= "0010";         -- dim gray
          end case;
        end if;
      end if;
    end if;
  end process;

  -- ============================================================
  -- Output assignments
  -- ============================================================
  hsync_o <= hsync_r;
  vsync_o <= vsync_r;
  r_o     <= r_r;
  g_o     <= g_r;
  b_o     <= b_r;

end architecture;
