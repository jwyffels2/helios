library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity vga_640x480_timing is
  port (
    clk_i    : in  std_ulogic;
    rstn_i   : in  std_ulogic;
    pix_ce_i : in  std_ulogic;

    hsync_o  : out std_ulogic;
    vsync_o  : out std_ulogic;
    active_o : out std_ulogic;
    x_o      : out unsigned(9 downto 0);
    y_o      : out unsigned(9 downto 0)
  );
end entity;

architecture rtl of vga_640x480_timing is

  constant H_VISIBLE_C : integer := 640;
  constant H_FRONT_C   : integer := 16;
  constant H_SYNC_C    : integer := 96;
  constant H_BACK_C    : integer := 48;
  constant H_TOTAL_C   : integer := 800;

  constant V_VISIBLE_C : integer := 480;
  constant V_FRONT_C   : integer := 10;
  constant V_SYNC_C    : integer := 2;
  constant V_BACK_C    : integer := 33;
  constant V_TOTAL_C   : integer := 525;

  signal h_cnt : unsigned(9 downto 0) := (others => '0');
  signal v_cnt : unsigned(9 downto 0) := (others => '0');

  signal hsync_n : std_ulogic := '1';
  signal vsync_n : std_ulogic := '1';
  signal active  : std_ulogic := '0';

begin

  process(clk_i)
  begin
    if rising_edge(clk_i) then
      if rstn_i = '0' then
        h_cnt <= (others => '0');
        v_cnt <= (others => '0');
      elsif pix_ce_i = '1' then
        if h_cnt = to_unsigned(H_TOTAL_C - 1, h_cnt'length) then
          h_cnt <= (others => '0');

          if v_cnt = to_unsigned(V_TOTAL_C - 1, v_cnt'length) then
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

  process(h_cnt, v_cnt)
    variable h_i : integer;
    variable v_i : integer;
  begin
    h_i := to_integer(h_cnt);
    v_i := to_integer(v_cnt);

    if (h_i < H_VISIBLE_C) and (v_i < V_VISIBLE_C) then
      active <= '1';
    else
      active <= '0';
    end if;

    if (h_i >= (H_VISIBLE_C + H_FRONT_C)) and
       (h_i <  (H_VISIBLE_C + H_FRONT_C + H_SYNC_C)) then
      hsync_n <= '0';
    else
      hsync_n <= '1';
    end if;

    if (v_i >= (V_VISIBLE_C + V_FRONT_C)) and
       (v_i <  (V_VISIBLE_C + V_FRONT_C + V_SYNC_C)) then
      vsync_n <= '0';
    else
      vsync_n <= '1';
    end if;
  end process;

  hsync_o  <= hsync_n;
  vsync_o  <= vsync_n;
  active_o <= active;
  x_o      <= h_cnt;
  y_o      <= v_cnt;

end architecture;
