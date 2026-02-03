library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- vram_bram_stub.vhd
-- Simple dual-port VRAM storage block (BRAM-inferable in Vivado).
--
-- This file lives under vga_fb/vhdl and is intended as a lightweight building
-- block that is compatible with the rtl/helios.vhdl reset/type conventions:
--   - clk_i  : std_ulogic
--   - rstn_i : active-low reset (resets only the read-data register)
--
-- Port model:
--   - Write port: byte enables (wr_be_i) over DATA_WIDTH
--   - Read port: synchronous registered output (rd_data_o)

entity vram_bram_stub is
  generic (
    ADDR_WIDTH : natural := 16;
    DATA_WIDTH : natural := 32
  );
  port (
    clk_i   : in  std_ulogic;
    rstn_i  : in  std_ulogic;

    wr_en_i   : in  std_ulogic;
    wr_addr_i : in  unsigned(ADDR_WIDTH-1 downto 0);
    wr_data_i : in  std_ulogic_vector(DATA_WIDTH-1 downto 0);
    wr_be_i   : in  std_ulogic_vector((DATA_WIDTH/8)-1 downto 0);

    rd_en_i   : in  std_ulogic;
    rd_addr_i : in  unsigned(ADDR_WIDTH-1 downto 0);
    rd_data_o : out std_ulogic_vector(DATA_WIDTH-1 downto 0)
  );
end entity;

architecture rtl of vram_bram_stub is
  constant DEPTH_C : natural := 2 ** ADDR_WIDTH;
  constant BYTES_C : natural := DATA_WIDTH / 8;

  type ram_t is array (0 to DEPTH_C-1) of std_ulogic_vector(DATA_WIDTH-1 downto 0);
  signal ram : ram_t := (others => (others => '0'));

  -- Hint Vivado toward block RAM
  attribute ram_style : string;
  attribute ram_style of ram : signal is "block";

  signal rd_data_r : std_ulogic_vector(DATA_WIDTH-1 downto 0) := (others => '0');
begin
  -- Sanity: we rely on byte lanes for BE.
  assert (DATA_WIDTH mod 8) = 0
    report "vram_bram_stub: DATA_WIDTH must be a multiple of 8"
    severity failure;

  -- Write port (byte enables)
  process(clk_i)
    variable waddr : integer;
    variable w     : std_ulogic_vector(DATA_WIDTH-1 downto 0);
  begin
    if rising_edge(clk_i) then
      if wr_en_i = '1' then
        waddr := to_integer(wr_addr_i);
        w := ram(waddr);
        for b in 0 to BYTES_C-1 loop
          if wr_be_i(b) = '1' then
            w((8*b+7) downto (8*b)) := wr_data_i((8*b+7) downto (8*b));
          end if;
        end loop;
        ram(waddr) <= w;
      end if;
    end if;
  end process;

  -- Read port (registered output)
  process(clk_i)
    variable raddr : integer;
  begin
    if rising_edge(clk_i) then
      if rstn_i = '0' then
        rd_data_r <= (others => '0');
      else
        if rd_en_i = '1' then
          raddr := to_integer(rd_addr_i);
          rd_data_r <= ram(raddr);
        else
          rd_data_r <= (others => '0');
        end if;
      end if;
    end if;
  end process;

  rd_data_o <= rd_data_r;
end architecture;
