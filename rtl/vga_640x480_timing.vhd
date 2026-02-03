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
--   - Create a separate pixel clock (it generates an internal clock-enable)
--
-- Clocking model (important for clean implementation):
--   - clk_i is the *real* FPGA clock (e.g., 100 MHz on Basys3)
--   - A 1-cycle "pixel strobe" is generated internally at (clk_i / PIX_CE_DIV)
--     For 640x480@60, pixel rate is ~25 MHz. With a 100 MHz clk_i, use
--     PIX_CE_DIV=4. If clk_i is already your pixel clock, use PIX_CE_DIV=1.
--   - Counters only advance on that pixel strobe
--
-- Notes:
--   - x_o/y_o always reflect the raw counters (including porches + sync)
--     ACTIVE indicates whether x_o<640 and y_o<480.
-- ============================================================================

entity vga_640x480_timing is
  generic (
    -- Pixel strobe divider relative to clk_i.
    --   Basys3: 100 MHz / 4 = 25 MHz pixel rate (close enough for many monitors).
    --   If you provide a true pixel clock on clk_i (e.g., via MMCM), set this to 1.
    PIX_CE_DIV : positive := 4
  );
  port (
    clk_i    : in  std_ulogic;  -- system clock (e.g., 100 MHz)
    rstn_i   : in  std_ulogic;  -- ACTIVE-LOW synchronous reset (matches NEORV32 style)

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

  -- clk_i -> pixel-rate strobe (1-cycle) generator
  signal pix_div_cnt : integer range 0 to PIX_CE_DIV-1 := 0;

  -- --------------------------------------------------------------------------
  -- Decoded outputs (combinational from counters)
  -- --------------------------------------------------------------------------
  signal hsync_n : std_ulogic := '1'; -- active-low
  signal vsync_n : std_ulogic := '1'; -- active-low
  signal active  : std_ulogic := '0'; -- '1' in visible region

begin

  ----------------------------------------------------------------------------
  -- Pixel counters (advance ONLY at the pixel strobe rate)
  -- Synchronous reset brings counters back to 0,0.
  ----------------------------------------------------------------------------
  process(clk_i)
    variable tick : boolean;
  begin
    if rising_edge(clk_i) then
      if rstn_i = '0' then
        pix_div_cnt <= 0;
        h_cnt <= (others => '0');
        v_cnt <= (others => '0');

      else
        -- Generate 1-cycle pixel-rate strobe (tick) every PIX_CE_DIV cycles.
        tick := (pix_div_cnt = (PIX_CE_DIV - 1));
        if tick then
          pix_div_cnt <= 0;
        else
          pix_div_cnt <= pix_div_cnt + 1;
        end if;

        if tick then
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
