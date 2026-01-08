library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- ============================================================================
-- Wishbone slave that exposes VRAM as a memory-mapped window
-- Base: 0xF0000000 (typical NEORV32 external IO base)
-- Size: 0x5000 bytes (covers 19200B framebuffer, rounded up)
--
-- Writes:
--   - wb_sel_i -> cpu_be
--   - wb_dat_i -> cpu_wdata
--   - (wb_adr_i - BASE) -> cpu_addr (byte offset)
--   - ack only when vram_ready='1'
-- ============================================================================
entity vram_wb_slave is
  generic (
    BASE_ADDR : unsigned(31 downto 0) := x"F0000000";
    WIN_SIZE  : unsigned(31 downto 0) := x"00005000"  -- 20,480 bytes
  );
  port (
    clk_i : in  std_ulogic;
    rst_i : in  std_ulogic;

    -- Wishbone slave interface
    wb_cyc_i : in  std_ulogic;
    wb_stb_i : in  std_ulogic;
    wb_we_i  : in  std_ulogic;
    wb_adr_i : in  unsigned(31 downto 0);
    wb_dat_i : in  std_ulogic_vector(31 downto 0);
    wb_sel_i : in  std_ulogic_vector(3 downto 0);

    wb_ack_o : out std_ulogic;
    wb_dat_o : out std_ulogic_vector(31 downto 0);

    -- To your VRAM write interface
    vram_ready_i : in  std_ulogic;  -- connect to vram_rgb332_dp.cpu_ready_o
    cpu_we_o     : out std_ulogic;
    cpu_be_o     : out std_ulogic_vector(3 downto 0);
    cpu_addr_o   : out unsigned(31 downto 0);
    cpu_wdata_o  : out std_ulogic_vector(31 downto 0)
  );
end entity;

architecture rtl of vram_wb_slave is

  signal hit      : std_ulogic;
  signal req      : std_ulogic;
  signal ack_r    : std_ulogic := '0';

  function in_range(a, base, size : unsigned(31 downto 0)) return boolean is
  begin
    return (a >= base) and (a < (base + size));
  end function;

begin

  -- decode window
  hit <= '1' when in_range(wb_adr_i, BASE_ADDR, WIN_SIZE) else '0';

  -- a valid bus request to this device
  req <= wb_cyc_i and wb_stb_i and hit;

  process(clk_i)
    variable off : unsigned(31 downto 0);
  begin
    if rising_edge(clk_i) then
      if rst_i = '1' then
        ack_r     <= '0';
        cpu_we_o  <= '0';
        cpu_be_o  <= (others => '0');
        cpu_addr_o<= (others => '0');
        cpu_wdata_o <= (others => '0');
        wb_dat_o  <= (others => '0');
      else
        -- default outputs
        ack_r    <= '0';
        cpu_we_o <= '0';
        wb_dat_o <= (others => '0'); -- reads not implemented (yet)

        if req = '1' then
          -- only support writes for now
          if wb_we_i = '1' then
            if vram_ready_i = '1' then
              off := wb_adr_i - BASE_ADDR;

              -- drive VRAM write-side interface (byte addressed)
              cpu_addr_o  <= off;
              cpu_wdata_o <= wb_dat_i;
              cpu_be_o    <= wb_sel_i;
              cpu_we_o    <= '1';

              -- acknowledge this WB transfer
              ack_r <= '1';
            else
              -- stall by withholding ack until VRAM ready
              ack_r <= '0';
            end if;
          else
            -- read not supported: ack immediately with 0s (safe default)
            ack_r <= '1';
            wb_dat_o <= (others => '0');
          end if;
        end if;

      end if;
    end if;
  end process;

  wb_ack_o <= ack_r;

end architecture;
