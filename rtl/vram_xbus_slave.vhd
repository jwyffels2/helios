library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- This block exposes the framebuffer BRAM through the NEORV32 external bus.
-- The CPU sees a byte-addressed MMIO window starting at 0xF0000000, while the
-- VRAM write side receives a 32-bit word, byte enables, and a byte offset.
--
-- The important behavior for teammates to keep in mind is the XBUS handshake.
-- NEORV32 can pulse STB for one cycle and then leave CYC asserted until ACK is
-- returned. That means we cannot depend on STB staying high while the VRAM
-- write path gets ready. Instead, this block latches the request and completes
-- it later when vram_ready_i says the BRAM-side serializer can accept it.
--
-- Reads are intentionally stubbed out for now. The framebuffer path is
-- currently write-only from software, so unsupported reads return zero and are
-- acknowledged immediately.
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

  -- 'hit' is high when the current XBUS address lands in the framebuffer MMIO
  -- window. 'req_new' captures a new transfer targeting this device. 'ack_r'
  -- is pulsed for one cycle when we complete the pending request.
  signal hit     : std_ulogic;
  signal req_new : std_ulogic;
  signal ack_r   : std_ulogic := '0';

  -- Small helper so the address decode reads clearly at the call site.
  function in_range(a, base, size : unsigned(31 downto 0)) return boolean is
  begin
    return (a >= base) and (a < (base + size));
  end function;

  -- Latched bus transaction. Once captured, the request is held here until the
  -- VRAM side is ready to consume it.
  signal pend     : std_ulogic := '0';
  signal pend_we  : std_ulogic := '0';
  signal pend_adr : unsigned(31 downto 0) := (others => '0');
  signal pend_dat : std_ulogic_vector(31 downto 0) := (others => '0');
  signal pend_sel : std_ulogic_vector(3 downto 0) := (others => '0');

begin

  -- Decode whether the live XBUS address targets the framebuffer window.
  hit <= '1' when in_range(unsigned(xbus_adr_i), BASE_ADDR, WIN_SIZE) else '0';

  -- Capture the incoming request pulse while it is visible on the bus.
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
        -- Default outputs every cycle. If a request completes below, these are
        -- overwritten for that cycle only.
        ack_r     <= '0';
        cpu_we_o  <= '0';
        xbus_dat_o <= (others => '0');

        -- Latch a new request only when no earlier request is waiting. If one
        -- arrives while we're busy, the bus master will keep retrying because
        -- CYC stays high until it sees ACK.
        if (pend = '0') and (req_new = '1') then
          pend     <= '1';
          pend_we  <= xbus_we_i;
          pend_adr <= unsigned(xbus_adr_i);
          pend_dat <= xbus_dat_i;
          pend_sel <= xbus_sel_i;
        end if;

        -- Complete the buffered access when the target side can accept it.
        if pend = '1' then
          if pend_we = '1' then
            -- Writes wait for the VRAM-side serializer to report ready. This
            -- keeps the CPU-facing handshake aligned with actual acceptance of
            -- the request.
            if vram_ready_i = '1' then
              off := pend_adr - BASE_ADDR;

              -- The VRAM module expects a byte offset within the framebuffer
              -- window plus the original word data and byte enables.
              cpu_addr_o  <= off;
              cpu_wdata_o <= pend_dat;
              cpu_be_o    <= pend_sel;
              cpu_we_o    <= '1';

              -- Acknowledge only after the VRAM side has actually accepted the
              -- transfer, so software never observes a dropped write.
              ack_r <= '1';
              pend  <= '0';
            end if;
          else
            -- Reads are not part of the current framebuffer contract. Return
            -- zero so software gets a deterministic result instead of a bus
            -- hang while the read path is still unimplemented.
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

