-- ============================================================================
-- helios.vhdl
--
-- Framebuffer-backed VGA output for Basys3 (Artix-7).
--  - Input clock: 100 MHz
--  - Pixel clock: 25 MHz (100/4)
--  - VGA timing: 640x480 @ 60 Hz (timing-only module provides x/y/active + syncs)
--  - Framebuffer: 160x120 RGB332 (8-bit), scaled up 4x to fill 640x480
--  - Test writer: fills framebuffer once after reset with vertical color bars
--
-- Key detail:
--  The framebuffer read port is synchronous and registered (1-cycle latency).
--  Therefore, HSYNC/VSYNC/ACTIVE are delayed by 1 pixel clock to align with
--  the pixel data returning from BRAM.
-- ============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity helios is
  port (
    clk_i  : in  std_ulogic;  -- 100 MHz on Basys3
    rst_i  : in  std_ulogic;  -- ACTIVE-HIGH reset

    vga_hsync_o : out std_ulogic;
    vga_vsync_o : out std_ulogic;
    vga_r_o     : out std_ulogic_vector(3 downto 0);
    vga_g_o     : out std_ulogic_vector(3 downto 0);
    vga_b_o     : out std_ulogic_vector(3 downto 0)
  );
end entity;

architecture rtl of helios is

  -- ============================================================
  -- Pixel clock generation
  -- ============================================================
  -- VGA 640x480@60 expects ~25.175 MHz pixel clock.
  -- Basys3 provides 100 MHz; we use a simple /4 divider to get 25 MHz.
  -- This is usually “good enough” for many monitors for bring-up.
  signal div_cnt : unsigned(1 downto 0) := (others => '0');
  signal pixclk  : std_ulogic := '0';

  -- ============================================================
  -- VGA timing signals (from timing-only module)
  -- ============================================================
  -- hsync_s/vsync_s: raw sync outputs from timing module (active-low)
  -- active_s: '1' only when x,y are in visible 640x480 region
  -- x_s, y_s: current pixel coordinates (0..639 and 0..479)
  signal hsync_s  : std_ulogic;
  signal vsync_s  : std_ulogic;
  signal active_s : std_ulogic;
  signal x_s      : unsigned(9 downto 0);
  signal y_s      : unsigned(9 downto 0);

  -- ============================================================
  -- BRAM read latency alignment
  -- ============================================================
  -- The framebuffer module returns dout_b_o REGISTERED (1-cycle latency).
  -- So the pixel value we output at time N corresponds to the address we
  -- presented at time N-1. To keep picture stable, we delay sync/active
  -- by exactly 1 pixel clock as well.
  signal hsync_d  : std_ulogic := '1';
  signal vsync_d  : std_ulogic := '1';
  signal active_d : std_ulogic := '0';

  -- ============================================================
  -- Framebuffer interface
  -- ============================================================
  -- Framebuffer stores 160x120 pixels, RGB332 format:
  --   bits [7:5] = Red   (3 bits)
  --   bits [4:2] = Green (3 bits)
  --   bits [1:0] = Blue  (2 bits)
  --
  -- Port A: write side (test writer / later CPU)
  -- Port B: read side (VGA)
  signal fb_we_a   : std_ulogic := '0';
  signal fb_addr_a : unsigned(14 downto 0) := (others => '0');
  signal fb_din_a  : std_ulogic_vector(7 downto 0) := (others => '0');

  signal fb_addr_b : unsigned(14 downto 0) := (others => '0');
  signal fb_dout_b : std_ulogic_vector(7 downto 0);

  -- ============================================================
  -- Scaling: map 640x480 -> 160x120 by dividing coordinates by 4
  -- ============================================================
  -- Horizontal: 640 / 4 = 160 => fb_x is 0..159 (8 bits)
  -- Vertical:   480 / 4 = 120 => fb_y is 0..119 (7 bits)
  --
  -- Using slices is equivalent to dividing by 4:
  --   x_s(9 downto 2) == floor(x_s / 4)
  --   y_s(8 downto 2) == floor(y_s / 4)
  signal fb_x : unsigned(7 downto 0);  -- 0..159
  signal fb_y : unsigned(6 downto 0);  -- 0..119

  -- ============================================================
  -- VGA DAC outputs (RGB444)
  -- ============================================================
  -- Basys3 VGA outputs are 4 bits per channel.
  -- We expand RGB332 -> RGB444 for display.
  signal r4 : std_ulogic_vector(3 downto 0) := (others => '0');
  signal g4 : std_ulogic_vector(3 downto 0) := (others => '0');
  signal b4 : std_ulogic_vector(3 downto 0) := (others => '0');

  -- ============================================================
  -- Test writer state
  -- ============================================================
  -- Simple bring-up writer that fills the whole framebuffer once after reset.
  -- After it reaches the last address, it stops writing permanently (wr_done=1).
  signal wr_addr : unsigned(14 downto 0) := (others => '0');
  signal wr_done : std_ulogic := '0';

begin

  -- ============================================================
  -- 25 MHz pixel clock divider (100 MHz / 4)
  -- ============================================================
  process(clk_i)
  begin
    if rising_edge(clk_i) then
      if rst_i = '1' then
        div_cnt <= (others => '0');
        pixclk  <= '0';
      else
        div_cnt <= div_cnt + 1;
        -- div_cnt(1) toggles every 2 input cycles => 25 MHz square wave
        pixclk  <= div_cnt(1);
      end if;
    end if;
  end process;

  -- ============================================================
  -- VGA timing generator
  -- ============================================================
  -- This module must output:
  --   - hsync_o, vsync_o (active-low pulses at proper intervals)
  --   - active_o (high only in visible area)
  --   - x_o, y_o pixel coordinates in visible region
  u_timing : entity work.vga_640x480_timing
    port map (
      pixclk_i => pixclk,
      rst_i    => rst_i,
      hsync_o  => hsync_s,
      vsync_o  => vsync_s,
      active_o => active_s,
      x_o      => x_s,
      y_o      => y_s
    );

  -- ============================================================
  -- Framebuffer BRAM (single-clock dual-port)
  -- ============================================================
  -- One clock (pixclk) drives both write and read. This is BRAM-friendly.
  u_fb : entity work.fb_bram_rgb332_160x120
    port map (
      clk_i    => pixclk,

      -- Write port A
      we_a_i   => fb_we_a,
      addr_a_i => fb_addr_a,
      din_a_i  => fb_din_a,

      -- Read port B
      addr_b_i => fb_addr_b,
      dout_b_o => fb_dout_b
    );

  -- ============================================================
  -- Scale VGA coordinates down by 4
  -- ============================================================
  -- x_s is 10 bits (0..639). Taking bits [9:2] yields 8 bits (0..159).
  fb_x <= x_s(9 downto 2);

  -- y_s is 10 bits (0..479). Taking bits [8:2] yields 7 bits (0..119).
  -- NOTE: This avoids the “7-bit vs 8-bit mismatch” error you saw earlier.
  fb_y <= y_s(8 downto 2);

  -- ============================================================
  -- Compute framebuffer read address
  -- ============================================================
  -- Framebuffer is 160 pixels wide, linear addressing:
  --   addr = fb_y * 160 + fb_x
  --
  -- Implement multiplication by 160 efficiently:
  --   160 = 128 + 32 => (y<<7) + (y<<5)
  -- Then add x. Resize carefully to keep Vivado happy about widths.
  fb_addr_b <= resize(
                (resize(fb_y, 15) sll 7) +
                (resize(fb_y, 15) sll 5) +
                resize(fb_x, 15),
                15
              );

  -- ============================================================
  -- Align sync/active with BRAM read latency and expand color
  -- ============================================================
  -- Because fb_dout_b is the pixel from the PREVIOUS cycle’s address,
  -- we delay the control signals by 1 cycle and output that pixel’s color.
  process(pixclk)
    variable px : std_ulogic_vector(7 downto 0);
  begin
    if rising_edge(pixclk) then
      if rst_i = '1' then
        hsync_d  <= '1';
        vsync_d  <= '1';
        active_d <= '0';

        r4 <= (others => '0');
        g4 <= (others => '0');
        b4 <= (others => '0');
      else
        -- Delay control signals one cycle
        hsync_d  <= hsync_s;
        vsync_d  <= vsync_s;
        active_d <= active_s;

        -- Pixel value returned from BRAM (registered)
        px := fb_dout_b;

        -- RGB332 -> RGB444 expansion
        -- Red:   3 bits -> 4 bits (replicate MSB)
        -- Green: 3 bits -> 4 bits (replicate MSB)
        -- Blue:  2 bits -> 4 bits (replicate pattern)
        r4 <= px(7 downto 5) & px(7);
        g4 <= px(4 downto 2) & px(4);
        b4 <= px(1 downto 0) & px(1 downto 0);
      end if;
    end if;
  end process;

  -- Drive VGA sync outputs (already properly aligned)
  vga_hsync_o <= hsync_d;
  vga_vsync_o <= vsync_d;

  -- Blank RGB outside active region to avoid “junk” during porch/sync
  vga_r_o <= r4 when active_d = '1' else (others => '0');
  vga_g_o <= g4 when active_d = '1' else (others => '0');
  vga_b_o <= b4 when active_d = '1' else (others => '0');

  -- ============================================================
  -- Test writer: fills framebuffer once after reset
  -- ============================================================
  -- Goal: prove the framebuffer path works end-to-end (writer -> BRAM -> VGA).
  -- Writes one pixel per 25 MHz clock into consecutive addresses.
  -- Pattern: 8 vertical bars across the 160-pixel-wide buffer (each 20 px wide).
  process(pixclk)
    variable a   : integer;  -- linear address 0..19199
    variable x   : integer;  -- x coordinate in 0..159 (a mod 160)
    variable bar : integer;  -- bar index 0..7

    -- RGB332 components as unsigned for easy concatenation
    variable r3  : unsigned(2 downto 0);
    variable g3  : unsigned(2 downto 0);
    variable b2  : unsigned(1 downto 0);
  begin
    if rising_edge(pixclk) then
      if rst_i = '1' then
        -- Reset writer state
        wr_addr   <= (others => '0');
        wr_done   <= '0';
        fb_we_a   <= '0';
        fb_addr_a <= (others => '0');
        fb_din_a  <= (others => '0');
      else
        if wr_done = '0' then
          -- Enable writes while filling
          fb_we_a   <= '1';
          fb_addr_a <= wr_addr;

          -- Decode current address into x position and select a color bar
          a   := to_integer(wr_addr);
          x   := a mod 160;
          bar := x / 20;  -- 160/8 = 20 pixels per bar

          -- Choose RGB332 colors for each bar
          case bar is
            when 0 => r3 := "111"; g3 := "000"; b2 := "00"; -- red
            when 1 => r3 := "111"; g3 := "111"; b2 := "00"; -- yellow
            when 2 => r3 := "000"; g3 := "111"; b2 := "00"; -- green
            when 3 => r3 := "000"; g3 := "111"; b2 := "11"; -- cyan
            when 4 => r3 := "000"; g3 := "000"; b2 := "11"; -- blue
            when 5 => r3 := "111"; g3 := "000"; b2 := "11"; -- magenta
            when 6 => r3 := "111"; g3 := "111"; b2 := "11"; -- white
            when others =>
              r3 := "001"; g3 := "001"; b2 := "01";         -- dim gray
          end case;

          -- Pack RGB332 into 8-bit pixel
          fb_din_a <= std_ulogic_vector(r3) &
                     std_ulogic_vector(g3) &
                     std_ulogic_vector(b2);

          -- Advance through all 19200 pixels then stop
          if wr_addr = to_unsigned(19199, wr_addr'length) then
            wr_done <= '1';
            fb_we_a <= '0';
          else
            wr_addr <= wr_addr + 1;
          end if;

        else
          -- After fill completes, keep write disabled
          fb_we_a <= '0';
        end if;
      end if;
    end if;
  end process;

end architecture;
