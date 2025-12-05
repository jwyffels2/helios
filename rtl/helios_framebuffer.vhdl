library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity helios_framebuffer is
  generic (
    FB_WIDTH   : natural := 320;
    FB_HEIGHT  : natural := 240;
    BPP        : natural := 8;
    ADDR_WIDTH : natural := 17  -- 2^ADDR_WIDTH >= FB_WIDTH*FB_HEIGHT
  );
  port (
    -- CPU / bus side (clk_cpu domain)
    clk_cpu   : in  std_ulogic;
    we_cpu    : in  std_ulogic;
    addr_cpu  : in  unsigned(ADDR_WIDTH-1 downto 0);
    din_cpu   : in  std_ulogic_vector(BPP-1 downto 0);
    dout_cpu  : out std_ulogic_vector(BPP-1 downto 0);

    -- VGA side (vga_clk domain, read-only)
    clk_vga   : in  std_logic;
    addr_vga  : in  unsigned(ADDR_WIDTH-1 downto 0);
    dout_vga  : out std_logic_vector(BPP-1 downto 0)
  );
end entity helios_framebuffer;

architecture rtl of helios_framebuffer is

  constant FB_SIZE : natural := FB_WIDTH * FB_HEIGHT;

  subtype pixel_t is std_ulogic_vector(BPP-1 downto 0);
  type ram_t is array (0 to FB_SIZE-1) of pixel_t;

  signal ram : ram_t := (others => (others => '0'));

begin

  -- CPU/bus port
  process(clk_cpu)
    variable idx : integer;
  begin
    if rising_edge(clk_cpu) then
      idx := to_integer(addr_cpu);
      if (idx >= 0) and (idx < FB_SIZE) then
        if we_cpu = '1' then
          ram(idx) <= din_cpu;
        end if;
        dout_cpu <= ram(idx);
      else
        dout_cpu <= (others => '0');
      end if;
    end if;
  end process;

  -- VGA/read-only port
  process(clk_vga)
    variable idx : integer;
  begin
    if rising_edge(clk_vga) then
      idx := to_integer(addr_vga);
      if (idx >= 0) and (idx < FB_SIZE) then
        dout_vga <= ram(idx);
      else
        dout_vga <= (others => '0');
      end if;
    end if;
  end process;

end architecture rtl;
