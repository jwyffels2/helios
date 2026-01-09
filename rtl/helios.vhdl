library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity helios is
  port (
    clk_i  : in  std_ulogic;  -- 100 MHz
    rst_i  : in  std_ulogic;  -- active-high (BTN C)

    vga_hsync_o : out std_ulogic;
    vga_vsync_o : out std_ulogic;
    vga_r_o     : out std_ulogic_vector(3 downto 0);
    vga_g_o     : out std_ulogic_vector(3 downto 0);
    vga_b_o     : out std_ulogic_vector(3 downto 0)
  );
end entity;

architecture rtl of helios is
  -- 640x480@60 timing (25 MHz-ish pixel rate is "close enough" for many monitors)
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

  -- Pixel enable: 100 MHz / 4 = 25 MHz effective pixel tick
  signal div4   : unsigned(1 downto 0) := (others => '0');
  signal pix_en : std_ulogic := '0';

  signal h_cnt : unsigned(9 downto 0) := (others => '0'); -- 0..799
  signal v_cnt : unsigned(9 downto 0) := (others => '0'); -- 0..524

  signal active : std_ulogic;
  signal hsync_n, vsync_n : std_ulogic;
begin

  -- generate pixel enable
  process(clk_i)
begin
    if rising_edge(clk_i) then
        if rst_i = '1' then
        div4   <= (others => '0');
        pix_en <= '0';
        else
        div4 <= div4 + 1;
        if div4 = "11" then
            pix_en <= '1';
        else
            pix_en <= '0';
        end if;
        end if;
    end if;
    end process;


  -- h/v counters advance only on pix_en
  process(clk_i)
  begin
    if rising_edge(clk_i) then
      if rst_i = '1' then
        h_cnt <= (others => '0');
        v_cnt <= (others => '0');
      else
        if pix_en = '1' then
          if h_cnt = to_unsigned(H_TOTAL-1, h_cnt'length) then
            h_cnt <= (others => '0');
            if v_cnt = to_unsigned(V_TOTAL-1, v_cnt'length) then
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

  -- active video
  active <= '1' when (to_integer(h_cnt) < H_VISIBLE and to_integer(v_cnt) < V_VISIBLE) else '0';

  -- syncs (active-low)
  hsync_n <= '0' when (to_integer(h_cnt) >= (H_VISIBLE + H_FRONT) and
                       to_integer(h_cnt) <  (H_VISIBLE + H_FRONT + H_SYNC)) else '1';

  vsync_n <= '0' when (to_integer(v_cnt) >= (V_VISIBLE + V_FRONT) and
                       to_integer(v_cnt) <  (V_VISIBLE + V_FRONT + V_SYNC)) else '1';

  vga_hsync_o <= hsync_n;
  vga_vsync_o <= vsync_n;

  -- visible test pattern: 8 vertical bars
  process(h_cnt, active)
    variable x : integer;
  begin
    if active = '0' then
      vga_r_o <= (others => '0');
      vga_g_o <= (others => '0');
      vga_b_o <= (others => '0');
    else
      x := to_integer(h_cnt); -- 0..639
      case x / 80 is
        when 0 => vga_r_o <= "1111"; vga_g_o <= "0000"; vga_b_o <= "0000"; -- red
        when 1 => vga_r_o <= "1111"; vga_g_o <= "1111"; vga_b_o <= "0000"; -- yellow
        when 2 => vga_r_o <= "0000"; vga_g_o <= "1111"; vga_b_o <= "0000"; -- green
        when 3 => vga_r_o <= "0000"; vga_g_o <= "1111"; vga_b_o <= "1111"; -- cyan
        when 4 => vga_r_o <= "0000"; vga_g_o <= "0000"; vga_b_o <= "1111"; -- blue
        when 5 => vga_r_o <= "1111"; vga_g_o <= "0000"; vga_b_o <= "1111"; -- magenta
        when 6 => vga_r_o <= "1111"; vga_g_o <= "1111"; vga_b_o <= "1111"; -- white
        when others =>
          vga_r_o <= "0010"; vga_g_o <= "0010"; vga_b_o <= "0010";         -- gray
      end case;
    end if;
  end process;

end architecture;
