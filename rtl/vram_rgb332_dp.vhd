library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- This module stores the framebuffer itself.
-- Each pixel is one RGB332 byte, so the BRAM is modeled as a byte array.
--
-- The CPU-facing side accepts a 32-bit word plus byte enables because that is
-- how NEORV32 drives XBUS writes. Rather than infer a more complex multi-port
-- or write-mask memory, we serialize the enabled lanes and perform one byte
-- write per clock. That keeps synthesis predictable and makes the ready/ack
-- behavior easy to reason about in simulation.
--
-- The VGA-side read port already exists so scanout can be added later. For the
-- current bring-up phase, the top level holds that side idle and uses this
-- module only as VRAM storage for software writes.
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

  -- Byte-wide framebuffer memory. Keeping the array element width at 8 bits
  -- matches the RGB332 storage format directly.
  type ram_t is array (0 to FB_SIZE-1) of std_ulogic_vector(7 downto 0);
  signal ram : ram_t := (others => (others => '0'));

  -- Hint Vivado toward block RAM
  attribute ram_style : string;
  attribute ram_style of ram : signal is "block";

  -- Registered VGA read output so scanout sees a stable one-cycle-late pixel.
  signal vga_rdata_r : std_ulogic_vector(7 downto 0) := (others => '0');

  -- Latched CPU write transaction. 'pend_addr' stores the aligned base address
  -- for the 32-bit word, while 'pend_be' tracks which byte lanes still need to
  -- be written into VRAM.
  signal pend      : std_ulogic := '0';
  signal pend_addr : unsigned(14 downto 0) := (others => '0');
  signal pend_data : std_ulogic_vector(31 downto 0) := (others => '0');
  signal pend_be   : std_ulogic_vector(3 downto 0) := (others => '0');

  -- Search pointer so enabled byte lanes are serviced deterministically.
  signal lane_ptr  : unsigned(1 downto 0) := (others => '0');

  -- Extract one byte lane from the 32-bit CPU word.
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

        -- Register the VGA-side byte read. Out-of-range reads return zero so
        -- future scanout logic has a defined behavior outside the image area.
        raddr := to_integer(vga_addr_i);
        if (raddr >= 0) and (raddr < FB_SIZE) then
          vga_rdata_r <= ram(raddr);
        else
          vga_rdata_r <= (others => '0');
        end if;

        -- Accept a new CPU write only when no earlier write is still being
        -- serialized. That contract is reflected back to the bus slave through
        -- cpu_ready_o.
        if (pend = '0') and (cpu_we_i = '1') then
          pend <= '1';

          -- Only the low 15 address bits are meaningful for this framebuffer.
          -- Align to the containing 32-bit word so lane 0..3 map cleanly onto
          -- byte writes for SB, SH, or full-word stores.
          pend_addr <= cpu_addr_i(14 downto 0) and to_unsigned (16#7FFC#, 15);

          pend_data <= cpu_wdata_i;
          pend_be   <= cpu_be_i;

          -- Always start lane scanning at 0 so simulations stay repeatable.
          lane_ptr <= (others => '0');
        end if;

        -- Service at most one byte lane per cycle. This is the key tradeoff in
        -- the design: simpler BRAM inference in exchange for multi-byte writes
        -- taking multiple clocks internally.
        if pend = '1' then
          found := false;
          sel_lane := 0;

          -- Search from the current pointer and wrap around so all requested
          -- lanes are eventually serviced even if they were sparse.
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
            -- Convert the aligned word base plus the selected lane into the
            -- final byte address inside the framebuffer.
            base  := to_integer(unsigned(pend_addr));
            waddr := base + sel_lane;

            if (waddr >= 0) and (waddr < FB_SIZE) then
              ram(waddr) <= lane_byte(pend_data, sel_lane);
            end if;

            -- Clear the lane we just committed so the request eventually drains.
            be_next := pend_be;
            be_next(sel_lane) := '0';
            pend_be <= be_next;

            -- Continue searching after this lane next cycle.
            lane_ptr <= to_unsigned((sel_lane + 1) mod 4, lane_ptr'length);

            -- Once every enabled lane has been consumed, the write transaction
            -- is finished and the module becomes ready for the next request.
            if be_next = "0000" then
              pend <= '0';
            end if;
          else
            -- A transaction with no enabled lanes is treated as a no-op.
            pend <= '0';
          end if;
        end if;

      end if;
    end if;
  end process;

  -- The bus slave is allowed to hand us a new write only when no earlier
  -- multi-lane transaction is still in progress.
  cpu_ready_o <= not pend;
  vga_rdata_o <= vga_rdata_r;

end architecture;

