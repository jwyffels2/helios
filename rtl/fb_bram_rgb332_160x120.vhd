-- ============================================================================
-- fb_bram_rgb332_160x120.vhd
--
-- Simple dual-port framebuffer implemented using inferred block RAM.
--
-- Resolution: 160 x 120 pixels
-- Total pixels: 19,200
-- Pixel format: RGB332 (8-bit)
--   [7:5] = Red   (3 bits)
--   [4:2] = Green (3 bits)
--   [1:0] = Blue  (2 bits)
--
-- Port A: Write port (used by test writer / future CPU)
-- Port B: Read port (used by VGA pixel pipeline)
--
-- IMPORTANT:
--   The read port is synchronous and REGISTERED.
--   This introduces a 1-cycle latency, which the VGA pipeline must account for
--   by delaying sync/active signals.
-- ============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity fb_bram_rgb332_160x120 is
  port (
    clk_i : in  std_ulogic;   -- Single clock for both read and write ports

    -- ============================================================
    -- Write Port (A)
    -- ============================================================
    we_a_i   : in  std_ulogic;                     -- Write enable
    addr_a_i : in  unsigned(14 downto 0);          -- Write address (0..19199)
    din_a_i  : in  std_ulogic_vector(7 downto 0);  -- Pixel data (RGB332)

    -- ============================================================
    -- Read Port (B)
    -- ============================================================
    addr_b_i : in  unsigned(14 downto 0);          -- Read address (0..19199)
    dout_b_o : out std_ulogic_vector(7 downto 0)   -- Registered pixel output
  );
end entity;

architecture rtl of fb_bram_rgb332_160x120 is

  -- ============================================================
  -- Framebuffer size constant
  -- ============================================================
  constant FB_SIZE : integer := 19200; -- 160 * 120

  -- ============================================================
  -- RAM storage declaration
  -- ============================================================
  -- This array will be inferred as block RAM by Vivado.
  type ram_t is array (0 to FB_SIZE-1) of std_ulogic_vector(7 downto 0);
  signal ram      : ram_t := (others => (others => '0'));

  -- Registered read data (1-cycle latency)
  signal dout_b_r : std_ulogic_vector(7 downto 0) := (others => '0');

  -- ============================================================
  -- Synthesis hint: force block RAM inference
  -- ============================================================
  attribute ram_style : string;
  attribute ram_style of ram : signal is "block";

begin

  -- ============================================================
  -- Dual-port synchronous RAM process
  -- ============================================================
  -- Both write and read are synchronous to clk_i.
  -- Write happens first; read data is registered.
  process(clk_i)
    variable a : integer; -- Write address as integer
    variable b : integer; -- Read address as integer
  begin
    if rising_edge(clk_i) then

      -- Convert unsigned addresses to integers for array indexing
      a := to_integer(addr_a_i);
      b := to_integer(addr_b_i);

      -- ----------------------------------------------------------
      -- Write port (A)
      -- ----------------------------------------------------------
      if we_a_i = '1' then
        -- Bounds check for safety (not strictly required in hardware,
        -- but useful for simulation clarity)
        if (a >= 0) and (a < FB_SIZE) then
          ram(a) <= din_a_i;
        end if;
      end if;

      -- ----------------------------------------------------------
      -- Read port (B) - registered output
      -- ----------------------------------------------------------
      if (b >= 0) and (b < FB_SIZE) then
        dout_b_r <= ram(b);
      else
        -- Out-of-range read returns black
        dout_b_r <= (others => '0');
      end if;

    end if;
  end process;

  -- ============================================================
  -- Output assignment
  -- ============================================================
  -- Expose registered read data to outside world
  dout_b_o <= dout_b_r;

end architecture;
