library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- ============================================================================
-- vga_640x480_timing
-- ============================================================================
-- VGA 640x480 @ 60 Hz timing generator (TIMING ONLY).
--
-- What this module does:
--   - Maintains horizontal/vertical pixel counters for the full 800x525 frame
--   - Generates HSYNC/VSYNC (active-low pulses)
--   - Generates an ACTIVE flag for the visible 640x480 region
--   - Outputs the current pixel coordinates (x_o, y_o)
--
-- What this module does NOT do:
--   - Generate any RGB/color data
--   - Read from or write to a framebuffer/VRAM
--   - Create a pixel clock (use a clock-enable instead)
--
-- Clocking model (important for clean implementation):
--   - clk_i is the *real* FPGA clock (e.g., 100 MHz on Basys3)
--   - pix_ce_i is a 1-cycle "pixel strobe" asserted at the pixel rate
--     For 640x480@60, pixel rate is ~25 MHz, so pix_ce_i should assert
--     once every 4 cycles of a 100 MHz clk_i.
--   - Counters only advance when pix_ce_i = '1'
--
-- Notes:
--   - x_o/y_o always reflect the raw counters (including porches + sync)
--     ACTIVE indicates whether x_o<640 and y_o<480.
-- ============================================================================

entity vga_640x480_timing is
  port (
    clk_i    : in  std_ulogic;  -- system clock (e.g., 100 MHz)
    rst_i    : in  std_ulogic;  -- ACTIVE-HIGH synchronous reset
    pix_ce_i : in  std_ulogic;  -- 1-cycle enable at pixel rate

    hsync_o  : out std_ulogic;  -- active-low horizontal sync
    vsync_o  : out std_ulogic;  -- active-low vertical sync
    active_o : out std_ulogic;  -- '1' in visible 640x480 region

    x_o      : out unsigned(9 downto 0); -- 0..799 (visible is 0..639)
    y_o      : out unsigned(9 downto 0)  -- 0..524 (visible is 0..479)
  );
end entity;

architecture rtl of vga_640x480_timing is

  -- --------------------------------------------------------------------------
  -- VGA timing constants for 640x480@60 ("classic VGA")
  -- --------------------------------------------------------------------------
  constant H_VISIBLE : integer := 640;
  constant H_FRONT   : integer := 16;
  constant H_SYNC    : integer := 96;
  constant H_BACK    : integer := 48;
  constant H_TOTAL   : integer := 800;

  constant V_VISIBLE : integer := 480;
  constant V_FRONT   : integer := 10;
  constant V_SYNC    : integer := 2;
  constant V_BACK    : integer := 33;
  constant V_TOTAL   : integer := 525;

  -- --------------------------------------------------------------------------
  -- Raw counters (full line/frame, including porches + sync)
  -- --------------------------------------------------------------------------
  signal h_cnt : unsigned(9 downto 0) := (others => '0'); -- 0..799
  signal v_cnt : unsigned(9 downto 0) := (others => '0'); -- 0..524

  -- --------------------------------------------------------------------------
  -- Decoded outputs (combinational from counters)
  -- --------------------------------------------------------------------------
  signal hsync_n : std_ulogic := '1'; -- active-low
  signal vsync_n : std_ulogic := '1'; -- active-low
  signal active  : std_ulogic := '0'; -- '1' in visible region

begin

  ----------------------------------------------------------------------------
  -- Pixel counters (advance ONLY when pix_ce_i='1')
  -- Synchronous reset brings counters back to 0,0.
  ----------------------------------------------------------------------------
  process(clk_i)
  begin
    if rising_edge(clk_i) then
      if rst_i = '1' then
        h_cnt <= (others => '0');
        v_cnt <= (others => '0');

      elsif pix_ce_i = '1' then
        -- End of line?
        if h_cnt = to_unsigned(H_TOTAL - 1, h_cnt'length) then
          h_cnt <= (others => '0');

          -- End of frame?
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

  ----------------------------------------------------------------------------
  -- Decode sync pulses + active region (purely combinational)
  ----------------------------------------------------------------------------
  process(h_cnt, v_cnt)
    variable h_i : integer;
    variable v_i : integer;
  begin
    h_i := to_integer(h_cnt);
    v_i := to_integer(v_cnt);

    -- Visible (active) region: 640x480 pixels
    if (h_i < H_VISIBLE) and (v_i < V_VISIBLE) then
      active <= '1';
    else
      active <= '0';
    end if;

    -- HSYNC pulse (active-low): occurs after visible + front porch
    if (h_i >= (H_VISIBLE + H_FRONT)) and
       (h_i <  (H_VISIBLE + H_FRONT + H_SYNC)) then
      hsync_n <= '0';
    else
      hsync_n <= '1';
    end if;

    -- VSYNC pulse (active-low): occurs after visible + front porch
    if (v_i >= (V_VISIBLE + V_FRONT)) and
       (v_i <  (V_VISIBLE + V_FRONT + V_SYNC)) then
      vsync_n <= '0';
    else
      vsync_n <= '1';
    end if;
  end process;

  ----------------------------------------------------------------------------
  -- Drive outputs
  ----------------------------------------------------------------------------
  hsync_o  <= hsync_n;
  vsync_o  <= vsync_n;
  active_o <= active;

  -- Raw counters are exported so upstream modules can compute VRAM addresses.
  x_o <= h_cnt;
  y_o <= v_cnt;

end architecture;
