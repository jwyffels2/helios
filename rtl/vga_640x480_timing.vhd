library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity vga_640x480_timing is
  port (
    pixclk_i : in  std_ulogic; -- 25 MHz
    rst_i    : in  std_ulogic; -- ACTIVE-HIGH

    hsync_o  : out std_ulogic;
    vsync_o  : out std_ulogic;
    active_o : out std_ulogic; -- 1 when x/y in 640x480 visible area

    x_o      : out unsigned(9 downto 0); -- 0..639 (during active)
    y_o      : out unsigned(9 downto 0)  -- 0..479 (during active)
  );
end entity;

architecture rtl of vga_640x480_timing is

  -- 640x480@60 "classic VGA"
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

  signal h_cnt   : unsigned(9 downto 0) := (others => '0'); -- 0..799
  signal v_cnt   : unsigned(9 downto 0) := (others => '0'); -- 0..524
  signal hsync_n : std_ulogic := '1';
  signal vsync_n : std_ulogic := '1';
  signal active  : std_ulogic := '0';

begin

  -- Counters
  process(pixclk_i)
  begin
    if rising_edge(pixclk_i) then
      if rst_i = '1' then
        h_cnt <= (others => '0');
        v_cnt <= (others => '0');
      else
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
  end process;

  -- Sync + active (combinational)
  process(h_cnt, v_cnt)
    variable h_i : integer;
    variable v_i : integer;
  begin
    h_i := to_integer(h_cnt);
    v_i := to_integer(v_cnt);

    -- active region
    if (h_i < H_VISIBLE) and (v_i < V_VISIBLE) then
      active <= '1';
    else
      active <= '0';
    end if;

    -- active-low sync pulses
    if (h_i >= (H_VISIBLE + H_FRONT)) and (h_i < (H_VISIBLE + H_FRONT + H_SYNC)) then
      hsync_n <= '0';
    else
      hsync_n <= '1';
    end if;

    if (v_i >= (V_VISIBLE + V_FRONT)) and (v_i < (V_VISIBLE + V_FRONT + V_SYNC)) then
      vsync_n <= '0';
    else
      vsync_n <= '1';
    end if;
  end process;

  hsync_o  <= hsync_n;
  vsync_o  <= vsync_n;
  active_o <= active;

  x_o <= h_cnt;
  y_o <= v_cnt;

end architecture;
