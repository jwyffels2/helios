library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.vga_fb_pkg.all;

-- Step 1 hardware: accept XBUS writes in the framebuffer window and ACK them.
-- No real memory yet; this is purely a contract + handshake stub.
entity vga_fb_xbus_stub is
  port (
    clk_i  : in  std_logic;
    rstn_i : in  std_logic;

    -- NEORV32 XBUS (Wishbone-like)
    xbus_adr_i : in  std_logic_vector(31 downto 0);
    xbus_dat_i : in  std_logic_vector(31 downto 0);
    xbus_we_i  : in  std_logic;  -- write enable
    xbus_sel_i : in  std_logic_vector(3 downto 0);
    xbus_stb_i : in  std_logic;
    xbus_cyc_i : in  std_logic;

    xbus_dat_o : out std_logic_vector(31 downto 0);
    xbus_ack_o : out std_logic;
    xbus_err_o : out std_logic
  );
end entity;

architecture rtl of vga_fb_xbus_stub is
  function in_range(a : std_logic_vector(31 downto 0)) return boolean is
    variable ua : unsigned(31 downto 0) := unsigned(a);
    variable ub : unsigned(31 downto 0) := unsigned(VGA_FB_BASE);
  begin
    return (ua >= ub) and (ua < (ub + VGA_FB_SIZE));
  end function;

  signal ack_r : std_logic := '0';
begin
  -- reads return 0 for now
  xbus_dat_o <= (others => '0');
  xbus_err_o <= '0';

  process(clk_i)
  begin
    if rising_edge(clk_i) then
      if rstn_i = '0' then
        ack_r <= '0';
      else
        -- default deassert
        ack_r <= '0';

        -- ACK any valid transaction in our address window
        if (xbus_cyc_i = '1') and (xbus_stb_i = '1') and in_range(xbus_adr_i) then
          -- For Step 1 we just acknowledge. Later: store xbus_dat_i into BRAM/VRAM.
          ack_r <= '1';
        end if;
      end if;
    end if;
  end process;

  xbus_ack_o <= ack_r;

end architecture;
