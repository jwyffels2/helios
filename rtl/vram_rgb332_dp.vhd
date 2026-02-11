library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- ============================================================
-- BRAM-inferable VRAM for 160x120 RGB332 (19200 bytes)
--
-- Memory is byte-wide (RGB332 per pixel).
-- VGA side reads 1 byte per pixel with 1-cycle registered latency.
--
-- CPU side presents a 32-bit write + byte enables (BE).
-- Internally, we serialize this into *one byte write per cycle* to keep
-- the RAM inference template simple and deterministic.
--
-- Addressing:
--   cpu_addr_i is a BYTE address within the VRAM window.
--   Only the low 15 bits are used (0..FB_SIZE-1).
--   Internally we align to a 32-bit word boundary (addr & ~3) and then write
--   base + lane_index (0..3) for each enabled byte lane.
--
-- Reset:
--   rstn_i is active-low. It resets only internal control/latched state; the
--   VRAM contents are not cleared.
-- ============================================================
entity vram_rgb332_dp is
  generic (
    FB_SIZE : integer := 19200
  );
  port (
    clk_i : in  std_ulogic;
    rstn_i : in  std_ulogic;

    cpu_we_i    : in  std_ulogic;
    cpu_be_i    : in  std_ulogic_vector(3 downto 0);
    cpu_addr_i  : in  unsigned(31 downto 0);
    cpu_wdata_i : in  std_ulogic_vector(31 downto 0);

    -- Indicates VRAM can accept a NEW 32-bit CPU write
    cpu_ready_o : out std_ulogic;

    vga_addr_i  : in  unsigned(14 downto 0);
    vga_rdata_o : out std_ulogic_vector(7 downto 0)
  );
end entity;

architecture rtl of vram_rgb332_dp is

  -- ------------------------------------------------------------
  -- Byte-wide framebuffer memory
  -- ------------------------------------------------------------
  type ram_t is array (0 to FB_SIZE-1) of std_ulogic_vector(7 downto 0);
  signal ram : ram_t := (others => (others => '0'));

  -- Hint Vivado toward block RAM
  attribute ram_style : string;
  attribute ram_style of ram : signal is "block";

  -- Registered VGA read output (1-cycle latency)
  signal vga_rdata_r : std_ulogic_vector(7 downto 0) := (others => '0');

  -- ------------------------------------------------------------
  -- Pending CPU write transaction (serialized to bytes)
  -- ------------------------------------------------------------
  signal pend      : std_ulogic := '0';
  signal pend_addr : unsigned(14 downto 0) := (others => '0');  -- aligned base byte address (addr & ~3)
  signal pend_data : std_ulogic_vector(31 downto 0) := (others => '0');
  signal pend_be   : std_ulogic_vector(3 downto 0) := (others => '0');

  signal lane_ptr  : unsigned(1 downto 0) := (others => '0');   -- starting lane to search (0..3)

  -- Extract the byte for lane i (0..3) from 32-bit word
  function lane_byte(d : std_ulogic_vector(31 downto 0); i : integer)
    return std_ulogic_vector is
  begin
    return d((8*i+7) downto (8*i));
  end function;

begin

  process(clk_i)
    variable raddr        : integer;

    -- For CPU write scheduling
    variable found        : boolean;
    variable sel_lane     : integer;
    variable search_start : integer;
    variable idx          : integer;

    variable base         : integer;
    variable waddr        : integer;
    variable be_next      : std_ulogic_vector(3 downto 0);
  begin
    if rising_edge(clk_i) then
      if rstn_i = '0' then
        vga_rdata_r <= (others => '0');

        pend      <= '0';
        pend_addr <= (others => '0');
        pend_data <= (others => '0');
        pend_be   <= (others => '0');
        lane_ptr  <= (others => '0');
      else

        -- ==========================================================
        -- VGA read port (registered)
        -- ==========================================================
        raddr := to_integer(vga_addr_i);
        if (raddr >= 0) and (raddr < FB_SIZE) then
          vga_rdata_r <= ram(raddr);
        else
          vga_rdata_r <= (others => '0');
        end if;

        -- ==========================================================
        -- Latch a new CPU write request when idle
        -- ==========================================================
        if (pend = '0') and (cpu_we_i = '1') then
          pend <= '1';

          -- Only low 15 bits are meaningful for 19200 bytes of VRAM.
          -- Align to 32-bit word boundary so byte-enables map to the correct
          -- byte address for sub-word CPU stores (SB/SH).
          pend_addr <= unsigned(std_logic_vector(cpu_addr_i(14 downto 2)) & "00");

          pend_data <= cpu_wdata_i;
          pend_be   <= cpu_be_i;

          -- Start scanning lanes at 0 (deterministic).
          lane_ptr <= (others => '0');
        end if;

        -- ==========================================================
        -- If pending, perform ONE byte write per cycle (if any lane enabled)
        -- ==========================================================
        if pend = '1' then
          found := false;
          sel_lane := 0;

          -- Search enabled lanes starting from lane_ptr, wrapping around
          search_start := to_integer(lane_ptr);
          for k in 0 to 3 loop
            idx := (search_start + k) mod 4;
            if pend_be(idx) = '1' then
              found := true;
              sel_lane := idx;
              exit;
            end if;
          end loop;

          if found then
            -- Compute write address: base + lane
            base  := to_integer(unsigned(pend_addr));
            waddr := base + sel_lane;

            if (waddr >= 0) and (waddr < FB_SIZE) then
              ram(waddr) <= lane_byte(pend_data, sel_lane);
            end if;

            -- Clear the lane we just wrote (so we eventually finish)
            be_next := pend_be;
            be_next(sel_lane) := '0';
            pend_be <= be_next;

            -- Advance pointer to lane after the one we just serviced
            lane_ptr <= to_unsigned((sel_lane + 1) mod 4, lane_ptr'length);

            -- If that was the last enabled byte, clear pending next cycle
            if be_next = "0000" then
              pend <= '0';
            end if;
          else
            -- No enabled lanes => complete transaction
            pend <= '0';
          end if;
        end if;

      end if;
    end if;
  end process;

  cpu_ready_o <= not pend;
  vga_rdata_o <= vga_rdata_r;

end architecture;

