-- rtl/vga_fb/vga_fb_mem.vhd
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.vga_fb_pkg.all;

entity vga_fb_mem is
  port (
    clk_i  : in  std_logic;
    rstn_i : in  std_logic;

    -- XBUS write side
    xbus_adr_i : in  std_logic_vector(31 downto 0);
    xbus_dat_i : in  std_logic_vector(31 downto 0);
    xbus_we_i  : in  std_logic;
    xbus_sel_i : in  std_logic_vector(3 downto 0);
    xbus_stb_i : in  std_logic;
    xbus_cyc_i : in  std_logic;

    xbus_ack_o : out std_logic;
    xbus_err_o : out std_logic;

    -- VGA read side
    vga_x_i : in  unsigned(9 downto 0);
    vga_y_i : in  unsigned(9 downto 0);
    pixel_o : out std_logic_vector(7 downto 0)
  );
end entity;

architecture rtl of vga_fb_mem is

  constant FB_PIXELS : natural := VGA_FB_W * VGA_FB_H;

  type fb_mem_t is array (0 to FB_PIXELS-1) of std_logic_vector(7 downto 0);
  signal fb : fb_mem_t := (others => (others => '0'));

  signal ack_r : std_logic := '0';

  function fb_index(x, y : unsigned) return integer is
  begin
    return to_integer(y) * VGA_FB_W + to_integer(x);
  end function;

begin

  --------------------------------------------------------------------
  -- XBUS write logic
  --------------------------------------------------------------------
  process(clk_i)
    variable idx : integer;
  begin
    if rising_edge(clk_i) then
      if rstn_i = '0' then
        ack_r <= '0';
      else
        ack_r <= '0';

        if xbus_cyc_i = '1' and xbus_stb_i = '1' and xbus_we_i = '1' then
          -- byte address → pixel index
          idx := to_integer(unsigned(xbus_adr_i(15 downto 0)));

          if idx < FB_PIXELS then
            fb(idx) <= xbus_dat_i(7 downto 0);
            ack_r <= '1';
          end if;
        end if;
      end if;
    end if;
  end process;

  xbus_ack_o <= ack_r;
  xbus_err_o <= '0';

  --------------------------------------------------------------------
  -- VGA read path (combinational)
  --------------------------------------------------------------------
  process(vga_x_i, vga_y_i)
    variable i : integer;
  begin
    if (to_integer(vga_x_i) < VGA_FB_W) and
       (to_integer(vga_y_i) < VGA_FB_H) then
      i := fb_index(vga_x_i, vga_y_i);
      pixel_o <= fb(i);
    else
      pixel_o <= (others => '0');
    end if;
  end process;

end architecture;
