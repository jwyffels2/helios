library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Minimal 640x480@60Hz VGA timing generator
-- Reset polarity: rst_i is ACTIVE-HIGH
-- (matches your top-level mapping: rst_i => not rstn_core)

entity vga_fb_integration_stub is
  port (
    clk_i    : in  std_ulogic;  -- expects 25 MHz for correct 640x480@60
    rst_i    : in  std_ulogic;  -- active-high reset

    hsync_o  : out std_ulogic;
    vsync_o  : out std_ulogic;
    r_o      : out std_ulogic_vector(3 downto 0);
    g_o      : out std_ulogic_vector(3 downto 0);
    b_o      : out std_ulogic_vector(3 downto 0);

    -- Future CPU write interface (unused for now)
    fb_we_i    : in  std_ulogic;
    fb_addr_i  : in  std_ulogic_vector(15 downto 0);
    fb_data_i  : in  std_ulogic_vector(7 downto 0)
  );
end entity;

architecture rtl of vga_fb_integration_stub is

  -- 640x480 @ 60 Hz timing (pixel clock = 25.175 MHz nominal; 25.000 MHz usually works on many monitors)
  constant H_VISIBLE : integer := 640;
  constant H_FRONT   : integer := 16;
  constant H_SYNC    : integer := 96;
  constant H_BACK    : integer := 48;
  constant H_TOTAL   : integer := H_VISIBLE + H_FRONT + H_SYNC + H_BACK; -- 800

  constant V_VISIBLE : integer := 480;
  constant V_FRONT   : integer := 10;
  constant V_SYNC    : integer := 2;
  constant V_BACK    : integer := 33;
  constant V_TOTAL   : integer := V_VISIBLE + V_FRONT + V_SYNC + V_BACK; -- 525

  signal h_cnt : unsigned(9 downto 0) := (others => '0');  -- up to 799
  signal v_cnt : unsigned(9 downto 0) := (others => '0');  -- up to 524

  signal hsync_n : std_ulogic := '1';
  signal vsync_n : std_ulogic := '1';
  signal active  : std_ulogic := '0';

begin

  -- Counters
  process(clk_i)
  begin
    if rising_edge(clk_i) then
      if rst_i = '1' then
        h_cnt <= (others => '0');
        v_cnt <= (others => '0');
      else
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
      end if;
    end if;
  end process;

  -- Sync generation (VGA syncs are typically active-low)
  process(h_cnt, v_cnt)
    variable h_i : integer;
    variable v_i : integer;
  begin
    h_i := to_integer(h_cnt);
    v_i := to_integer(v_cnt);

    -- Active video region
    if (h_i < H_VISIBLE) and (v_i < V_VISIBLE) then
      active <= '1';
    else
      active <= '0';
    end if;

    -- HSYNC low during sync pulse
    if (h_i >= (H_VISIBLE + H_FRONT)) and (h_i < (H_VISIBLE + H_FRONT + H_SYNC)) then
      hsync_n <= '0';
    else
      hsync_n <= '1';
    end if;

    -- VSYNC low during sync pulse
    if (v_i >= (V_VISIBLE + V_FRONT)) and (v_i < (V_VISIBLE + V_FRONT + V_SYNC)) then
      vsync_n <= '0';
    else
      vsync_n <= '1';
    end if;
  end process;

  hsync_o <= hsync_n;
  vsync_o <= vsync_n;

  -- Simple test pattern (no framebuffer yet):
  -- Visible area shows vertical color bars so you can confirm timing + pinout.
  process(h_cnt, v_cnt, active)
    variable x : integer;
  begin
    if active = '0' then
      r_o <= (others => '0');
      g_o <= (others => '0');
      b_o <= (others => '0');
    else
      x := to_integer(h_cnt); -- 0..639

      -- 8 bars across the screen (each 80 px)
      case x / 80 is
        when 0 => r_o <= "1111"; g_o <= "0000"; b_o <= "0000"; -- red
        when 1 => r_o <= "1111"; g_o <= "1111"; b_o <= "0000"; -- yellow
        when 2 => r_o <= "0000"; g_o <= "1111"; b_o <= "0000"; -- green
        when 3 => r_o <= "0000"; g_o <= "1111"; b_o <= "1111"; -- cyan
        when 4 => r_o <= "0000"; g_o <= "0000"; b_o <= "1111"; -- blue
        when 5 => r_o <= "1111"; g_o <= "0000"; b_o <= "1111"; -- magenta
        when 6 => r_o <= "1111"; g_o <= "1111"; b_o <= "1111"; -- white
        when others =>
          r_o <= "0010"; g_o <= "0010"; b_o <= "0010";         -- dim gray
      end case;
    end if;
  end process;

  -- Unused for now (keeps lint quiet; safe scaffold)
  -- (You can delete these once you implement the real write path.)
  -- pragma translate_off
  assert not (fb_we_i = '1') report "fb_we_i asserted but framebuffer not implemented yet" severity note;
  -- pragma translate_on

end architecture;
