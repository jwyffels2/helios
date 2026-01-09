library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity fb_bram_rgb332_160x120 is
  port (
    clk_i : in  std_ulogic;

    we_a_i   : in  std_ulogic;
    addr_a_i : in  unsigned(14 downto 0);
    din_a_i  : in  std_ulogic_vector(7 downto 0);

    addr_b_i : in  unsigned(14 downto 0);
    dout_b_o : out std_ulogic_vector(7 downto 0)
  );
end entity;

architecture rtl of fb_bram_rgb332_160x120 is
  constant FB_SIZE : integer := 19200;

  type ram_t is array (0 to FB_SIZE-1) of std_ulogic_vector(7 downto 0);
  signal ram      : ram_t := (others => (others => '0'));
  signal dout_b_r : std_ulogic_vector(7 downto 0) := (others => '0');

  attribute ram_style : string;
  attribute ram_style of ram : signal is "block";
begin

  process(clk_i)
    variable a : integer;
    variable b : integer;
  begin
    if rising_edge(clk_i) then
      a := to_integer(addr_a_i);
      b := to_integer(addr_b_i);

      if we_a_i = '1' then
        if (a >= 0) and (a < FB_SIZE) then
          ram(a) <= din_a_i;
        end if;
      end if;

      if (b >= 0) and (b < FB_SIZE) then
        dout_b_r <= ram(b);
      else
        dout_b_r <= (others => '0');
      end if;
    end if;
  end process;

  dout_b_o <= dout_b_r;

end architecture;
