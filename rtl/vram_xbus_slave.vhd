library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- ============================================================================
-- NEORV32 XBUS slave exposing VRAM as a memory-mapped window.
--
-- Base: 0xF0000000 (typical NEORV32 uncached/external bus region)
-- Size: 0x5000 bytes (covers 19200B framebuffer, rounded up)
--
-- Writes:
--   - xbus_sel_i -> cpu_be
--   - xbus_dat_i -> cpu_wdata
--   - (xbus_adr_i - BASE) -> cpu_addr (byte offset)
--   - ack only when vram_ready_i='1'
--
-- Note on handshake:
--   NEORV32's XBUS may only pulse STB for a new access while keeping CYC high
--   until ACK. Therefore this block latches the request on (CYC & STB) and can
--   complete it later (when vram_ready_i='1') even if STB has already dropped.
-- ============================================================================
entity vram_xbus_slave is
  generic (
    BASE_ADDR : unsigned(31 downto 0) := x"F0000000";
    WIN_SIZE  : unsigned(31 downto 0) := x"00005000"  -- 20,480 bytes
  );
  port (
    clk_i  : in  std_ulogic;
    rstn_i : in  std_ulogic;

    -- XBUS slave interface
    xbus_cyc_i : in  std_ulogic;
    xbus_stb_i : in  std_ulogic;
    xbus_we_i  : in  std_ulogic;
    xbus_adr_i : in  std_ulogic_vector(31 downto 0);
    xbus_dat_i : in  std_ulogic_vector(31 downto 0);
    xbus_sel_i : in  std_ulogic_vector(3 downto 0);

    xbus_ack_o : out std_ulogic;
    xbus_dat_o : out std_ulogic_vector(31 downto 0);

    -- To VRAM write interface
    vram_ready_i : in  std_ulogic;  -- connect to vram_rgb332_dp.cpu_ready_o
    cpu_we_o     : out std_ulogic;
    cpu_be_o     : out std_ulogic_vector(3 downto 0);
    cpu_addr_o   : out unsigned(31 downto 0);
    cpu_wdata_o  : out std_ulogic_vector(31 downto 0)
  );
end entity;

architecture rtl of vram_xbus_slave is

  signal hit     : std_ulogic;
  signal req_new : std_ulogic;
  signal ack_r   : std_ulogic := '0';

  function in_range(a, base, size : unsigned(31 downto 0)) return boolean is
  begin
    return (a >= base) and (a < (base + size));
  end function;

  -- Latched bus transaction (request can be completed even if STB drops)
  signal pend     : std_ulogic := '0';
  signal pend_we  : std_ulogic := '0';
  signal pend_adr : unsigned(31 downto 0) := (others => '0');
  signal pend_dat : std_ulogic_vector(31 downto 0) := (others => '0');
  signal pend_sel : std_ulogic_vector(3 downto 0) := (others => '0');

begin

  -- decode window
  hit <= '1' when in_range(unsigned(xbus_adr_i), BASE_ADDR, WIN_SIZE) else '0';

  -- new bus request to this device (may be a pulse)
  req_new <= xbus_cyc_i and xbus_stb_i and hit;

  process(clk_i)
    variable off : unsigned(31 downto 0);
  begin
    if rising_edge(clk_i) then
      if rstn_i = '0' then
        ack_r      <= '0';
        pend       <= '0';
        pend_we    <= '0';
        pend_adr   <= (others => '0');
        pend_dat   <= (others => '0');
        pend_sel   <= (others => '0');
        cpu_we_o   <= '0';
        cpu_be_o   <= (others => '0');
        cpu_addr_o <= (others => '0');
        cpu_wdata_o <= (others => '0');
        xbus_dat_o <= (others => '0');
      else
        -- default outputs
        ack_r     <= '0';
        cpu_we_o  <= '0';
        xbus_dat_o <= (others => '0'); -- reads not implemented (yet)

        -- Latch a new request when idle. If a request arrives while we're busy,
        -- it will be retried by the bus master (CYC stays high until ACK).
        if (pend = '0') and (req_new = '1') then
          pend     <= '1';
          pend_we  <= xbus_we_i;
          pend_adr <= unsigned(xbus_adr_i);
          pend_dat <= xbus_dat_i;
          pend_sel <= xbus_sel_i;
        end if;

        -- Complete the pending access when possible.
        if pend = '1' then
          if pend_we = '1' then
            -- write
            if vram_ready_i = '1' then
              off := pend_adr - BASE_ADDR;

              -- drive VRAM write-side interface (byte addressed)
              cpu_addr_o  <= off;
              cpu_wdata_o <= pend_dat;
              cpu_be_o    <= pend_sel;
              cpu_we_o    <= '1';

              -- acknowledge this transfer
              ack_r <= '1';
              pend  <= '0';
            end if;
          else
            -- read not supported: ack immediately with 0s (safe default)
            ack_r     <= '1';
            xbus_dat_o <= (others => '0');
            pend      <= '0';
          end if;
        end if;

      end if;
    end if;
  end process;

  xbus_ack_o <= ack_r;

end architecture;

