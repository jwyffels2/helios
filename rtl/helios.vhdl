library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- ============================================================================
-- helios (Basys3 top-level, single-file)
-- ============================================================================
-- Purpose:
--   Board-safe top entity that exports ONLY the real Basys3 pins:
--     - clk_i (100 MHz), rst_i
--     - VGA HS/VS + RGB444
--
-- Framebuffer-backed VGA architecture:
--   1) Generate pix_ce: a 1-cycle enable every 4 cycles of clk_i (25 MHz equiv)
--   2) VGA timing generator advances one pixel when pix_ce='1'
--   3) Convert 640x480 coords -> 160x120 coords by /4 scaling
--   4) Read VRAM byte (RGB332) at fb_addr_b and expand to RGB444
--   5) Delay HS/VS/active 1 pixel (pix_ce) to align with registered VRAM read
--
-- CPU write-side interface:
--   - Kept INTERNAL as signals (cpu_we/be/addr/wdata)
--   - NOT exported as top-level ports (Basys3 does not have enough pins)
--   - For demo, an optional HW test writer drives these signals to fill VRAM
--
-- Notes:
--   - This file is the "placeable/programable" Basys3 top.
--   - The internal cpu_* bus is still a real RTL interface to VRAM and can be
--     later connected to NEORV32 bus logic INSIDE the FPGA (not via pins).
-- ============================================================================

entity helios is
  port (
    clk_i  : in  std_ulogic;  -- 100 MHz Basys3 clock
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
  -- Pixel strobe generation: 100 MHz -> 25 MHz equivalent
  -- ============================================================
  signal div_cnt : unsigned(1 downto 0) := (others => '0');
  signal pix_ce  : std_ulogic := '0';  -- 1-cycle strobe every 4 clk cycles

  -- ============================================================
  -- VGA timing (timing-only module)
  -- ============================================================
  signal hsync_s  : std_ulogic := '1';
  signal vsync_s  : std_ulogic := '1';
  signal active_s : std_ulogic := '0';
  signal x_s      : unsigned(9 downto 0) := (others => '0'); -- 0..799
  signal y_s      : unsigned(9 downto 0) := (others => '0'); -- 0..524

  -- Align timing to VRAM read latency (1 pixel)
  signal hsync_d  : std_ulogic := '1';
  signal vsync_d  : std_ulogic := '1';
  signal active_d : std_ulogic := '0';

  -- ============================================================
  -- VRAM read-side for VGA scanout (RGB332 @ 160x120)
  -- ============================================================
  signal fb_addr_b : unsigned(14 downto 0) := (others => '0'); -- 0..19199
  signal fb_px_b   : std_ulogic_vector(7 downto 0) := (others => '0'); -- RGB332

  -- 640x480 -> 160x120 by /4 scaling
  signal fb_x : unsigned(7 downto 0) := (others => '0'); -- 0..159
  signal fb_y : unsigned(6 downto 0) := (others => '0'); -- 0..119

  -- RGB444 expanded output
  signal r4 : std_ulogic_vector(3 downto 0) := (others => '0');
  signal g4 : std_ulogic_vector(3 downto 0) := (others => '0');
  signal b4 : std_ulogic_vector(3 downto 0) := (others => '0');

  -- ============================================================
  -- INTERNAL CPU write-side interface (not top-level pins)
  -- ============================================================
  signal cpu_we_i    : std_ulogic := '0';
  signal cpu_be_i    : std_ulogic_vector(3 downto 0) := (others => '0');
  signal cpu_addr_i  : unsigned(31 downto 0) := (others => '0');
  signal cpu_wdata_i : std_ulogic_vector(31 downto 0) := (others => '0');

  -- ============================================================
  -- Optional hardware test-writer (fills VRAM after reset)
  -- ============================================================
  constant ENABLE_HW_TEST_WRITER : boolean := false;

  signal wr_addr_byte : unsigned(14 downto 0) := (others => '0'); -- 0..19199
  signal wr_done      : std_ulogic := '0';

begin

  -- ============================================================
  -- pix_ce generation: one strobe per 4 cycles -> 25 MHz equivalent
  -- ============================================================
  process(clk_i)
  begin
    if rising_edge(clk_i) then
      if rst_i = '1' then
        div_cnt <= (others => '0');
        pix_ce  <= '0';
      else
        div_cnt <= div_cnt + 1;
        if div_cnt = "11" then
          pix_ce <= '1';
        else
          pix_ce <= '0';
        end if;
      end if;
    end if;
  end process;

  -- ============================================================
  -- VGA timing generator (timing-only)
  -- ============================================================
  u_timing : entity work.vga_640x480_timing
    port map (
      clk_i    => clk_i,
      rst_i    => rst_i,
      pix_ce_i => pix_ce,

      hsync_o  => hsync_s,
      vsync_o  => vsync_s,
      active_o => active_s,
      x_o      => x_s,
      y_o      => y_s
    );

  -- ============================================================
  -- Scale VGA coordinates down by /4 (only meaningful when active_s='1')
  -- ============================================================
  fb_x <= x_s(9 downto 2); -- 0..159 during visible region
  fb_y <= y_s(8 downto 2); -- 0..119 during visible region

  -- ============================================================
  -- Framebuffer address: addr = y*160 + x
  -- 160 = 128 + 32 => (y<<7) + (y<<5)
  -- ============================================================
  fb_addr_b <= resize(
                 (resize(fb_y, 15) sll 7) +
                 (resize(fb_y, 15) sll 5) +
                 resize(fb_x, 15),
                 15
               );

  -- ============================================================
  -- Demo-only hardware writer:
  -- Fills VRAM with an 8-bar test pattern in RGB332.
  -- Writes one byte at a time using cpu_* internal interface semantics.
  -- ============================================================
  gen_hw_writer : if ENABLE_HW_TEST_WRITER generate
    process(clk_i)
      variable x        : integer;
      variable bar      : integer;
      variable byte_val : std_ulogic_vector(7 downto 0);
      variable lane     : integer;
    begin
      if rising_edge(clk_i) then
        if rst_i = '1' then
          wr_addr_byte <= (others => '0');
          wr_done      <= '0';

          cpu_we_i     <= '0';
          cpu_be_i     <= (others => '0');
          cpu_addr_i   <= (others => '0');
          cpu_wdata_i  <= (others => '0');

        else
          -- Default: no write unless we assert one below
          cpu_we_i <= '0';
          cpu_be_i <= (others => '0');
          cpu_wdata_i <= (others => '0');

          -- Only write on pixel strobes (deterministic + lower toggle rate)
          if (pix_ce = '1') and (wr_done = '0') then
            -- Choose color based on X (8 vertical bars across 160 pixels)
            x   := to_integer(wr_addr_byte) mod 160;
            bar := x / 20;

            case bar is
              when 0      => byte_val := "11100000"; -- red    (R=7,G=0,B=0)
              when 1      => byte_val := "11111100"; -- yellow (R=7,G=7,B=0)
              when 2      => byte_val := "00011100"; -- green  (R=0,G=7,B=0)
              when 3      => byte_val := "00011111"; -- cyan   (R=0,G=7,B=3)
              when 4      => byte_val := "00000011"; -- blue   (R=0,G=0,B=3)
              when 5      => byte_val := "11100011"; -- magenta(R=7,G=0,B=3)
              when 6      => byte_val := "11111111"; -- white  (R=7,G=7,B=3)
              when others => byte_val := "00100101"; -- dim gray-ish
            end case;

            -- Byte address in cpu_addr_i (byte addressing)
            cpu_addr_i <= (others => '0');
            cpu_addr_i(14 downto 0) <= wr_addr_byte;

            -- Align byte into correct lane based on addr[1:0]
            lane := to_integer(wr_addr_byte(1 downto 0));
            case lane is
              when 0 =>
                cpu_wdata_i(7 downto 0) <= byte_val;
                cpu_be_i(0) <= '1';
              when 1 =>
                cpu_wdata_i(15 downto 8) <= byte_val;
                cpu_be_i(1) <= '1';
              when 2 =>
                cpu_wdata_i(23 downto 16) <= byte_val;
                cpu_be_i(2) <= '1';
              when others =>
                cpu_wdata_i(31 downto 24) <= byte_val;
                cpu_be_i(3) <= '1';
            end case;

            cpu_we_i <= '1';

            if wr_addr_byte = to_unsigned(19199, wr_addr_byte'length) then
              wr_done <= '1';
            else
              wr_addr_byte <= wr_addr_byte + 1;
            end if;
          end if;
        end if;
      end if;
    end process;
  end generate;

  gen_no_hw_writer : if not ENABLE_HW_TEST_WRITER generate
    -- In real NEORV32 integration, these cpu_* signals will be driven
    -- by the internal SoC bus logic (NOT by FPGA top-level pins).
    cpu_we_i    <= '0';
    cpu_be_i    <= (others => '0');
    cpu_addr_i  <= (others => '0');
    cpu_wdata_i <= (others => '0');
  end generate;

  -- ============================================================
  -- VRAM dual-port block:
  -- - CPU writes: 32-bit word + byte enables, byte-addressed window
  -- - VGA reads:  one RGB332 byte per pixel (fb_addr_b)
  -- ============================================================
  u_vram : entity work.vram_rgb332_dp
    port map (
      clk_i       => clk_i,

      cpu_we_i    => cpu_we_i,
      cpu_be_i    => cpu_be_i,
      cpu_addr_i  => cpu_addr_i,
      cpu_wdata_i => cpu_wdata_i,

      vga_addr_i  => fb_addr_b,
      vga_rdata_o => fb_px_b
    );

  -- ============================================================
  -- Pipeline align + RGB332 -> RGB444 expansion
  -- Update ONLY on pix_ce to stay aligned to timing pixel steps.
  -- ============================================================
  process(clk_i)
    variable px : std_ulogic_vector(7 downto 0);
  begin
    if rising_edge(clk_i) then
      if rst_i = '1' then
        hsync_d  <= '1';
        vsync_d  <= '1';
        active_d <= '0';
        r4 <= (others => '0');
        g4 <= (others => '0');
        b4 <= (others => '0');

      elsif pix_ce = '1' then
        -- Delay timing to match registered VRAM read behavior
        hsync_d  <= hsync_s;
        vsync_d  <= vsync_s;
        active_d <= active_s;

        px := fb_px_b;

        -- Expand RGB332 -> RGB444
        r4 <= px(7 downto 5) & px(7);
        g4 <= px(4 downto 2) & px(4);
        b4 <= px(1 downto 0) & px(1 downto 0);
      end if;
    end if;
  end process;

  -- ============================================================
  -- VGA outputs (blank outside active area)
  -- ============================================================
  vga_hsync_o <= hsync_d;
  vga_vsync_o <= vsync_d;

  vga_r_o <= r4 when active_d = '1' else (others => '0');
  vga_g_o <= g4 when active_d = '1' else (others => '0');
  vga_b_o <= b4 when active_d = '1' else (others => '0');

end architecture;
