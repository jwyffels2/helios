@'
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- vram_bram_stub.vhd
-- Placeholder VRAM storage block (eventually BRAM or external memory).
-- Scaffold-only: currently returns zeros.

entity vram_bram_stub is
  generic (
    ADDR_WIDTH : natural := 16;
    DATA_WIDTH : natural := 32
  );
  port (
    clk_i     : in  std_logic;
    wr_en_i   : in  std_logic;
    wr_addr_i : in  std_logic_vector(ADDR_WIDTH-1 downto 0);
    wr_data_i : in  std_logic_vector(DATA_WIDTH-1 downto 0);
    wr_be_i   : in  std_logic_vector((DATA_WIDTH/8)-1 downto 0);

    rd_en_i   : in  std_logic;
    rd_addr_i : in  std_logic_vector(ADDR_WIDTH-1 downto 0);
    rd_data_o : out std_logic_vector(DATA_WIDTH-1 downto 0)
  );
end entity;

architecture rtl of vram_bram_stub is
begin
  -- TODO: Replace with true dual-port RAM (write port + read port).
  -- TODO: Confirm VGA read bandwidth requirements.
  -- TODO: Confirm if BRAM capacity is sufficient for desired resolution.

  rd_data_o <= (others => '0');
end architecture;
'@ | Set-Content -Encoding UTF8 vga_fb\vhdl\vram_bram_stub.vhd
