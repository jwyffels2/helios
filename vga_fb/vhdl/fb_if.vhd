@'
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- fb_if.vhd
-- Framebuffer interface stub.
-- Intended to sit between a writer (NEORV32 bus / DMA / test generator)
-- and the VGA scanout path (pixel fetch by X/Y).
--
-- NOTE: This is a scaffold-only module. No functional behavior is guaranteed.

entity fb_if is
  generic (
    ADDR_WIDTH : natural := 16; -- placeholder, TBD by VRAM size
    DATA_WIDTH : natural := 32  -- 32-bit writes for CPU friendliness
  );
  port (
    clk_i    : in  std_logic;
    rstn_i   : in  std_logic;

    -- Write-side interface (future: NEORV32 external bus adapter)
    wr_en_i  : in  std_logic;
    wr_addr_i: in  std_logic_vector(ADDR_WIDTH-1 downto 0);
    wr_data_i: in  std_logic_vector(DATA_WIDTH-1 downto 0);
    wr_be_i  : in  std_logic_vector((DATA_WIDTH/8)-1 downto 0); -- byte enables
    wr_ack_o : out std_logic;

    -- Read-side interface for VGA scanout (future: pixel fetch by x/y)
    rd_en_i  : in  std_logic;
    rd_addr_i: in  std_logic_vector(ADDR_WIDTH-1 downto 0);
    rd_data_o: out std_logic_vector(DATA_WIDTH-1 downto 0);
    rd_ack_o : out std_logic
  );
end entity;

architecture rtl of fb_if is
begin
  -- TODO: Implement arbitration between writer and scanout reader.
  -- TODO: Define VRAM address mapping (RGB332 / RGB565 / etc).
  -- TODO: Decide on sync/latency requirements for scanout.

  wr_ack_o  <= '0';
  rd_ack_o  <= '0';
  rd_data_o <= (others => '0');
end architecture;
'@ | Set-Content -Encoding UTF8 vga_fb\vhdl\fb_if.vhd
