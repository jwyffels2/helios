library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity helios_vga_xbus is
  generic (
    FB_ADDR_WIDTH   : natural := 17;  -- enough bits for VRAM size
    FB_BPP          : natural := 8;   -- bits per pixel on VRAM port
    VRAM_REGION_SEL : std_ulogic_vector(3 downto 0) := "0001"  -- xbus_adr_i(15..12)
  );
  port (
    -- System clock / reset
    clk_i    : in  std_ulogic;
    rstn_i   : in  std_ulogic;  -- active-low

    -- XBUS (NEORV32 external bus) slave side
    xbus_adr_i : in  std_ulogic_vector(31 downto 0);
    xbus_dat_i : in  std_ulogic_vector(31 downto 0);
    xbus_dat_o : out std_ulogic_vector(31 downto 0);
    xbus_we_i  : in  std_ulogic;
    xbus_sel_i : in  std_ulogic_vector(3 downto 0);
    xbus_stb_i : in  std_ulogic;
    xbus_cyc_i : in  std_ulogic;
    xbus_ack_o : out std_ulogic;
    xbus_err_o : out std_ulogic;
    xbus_cti_i : in  std_ulogic_vector(2 downto 0);
    xbus_tag_i : in  std_ulogic_vector(2 downto 0);

    -----------------------------------------------------------------
    -- Register outputs (to top-level helios_vga)
    -----------------------------------------------------------------
    ctrl_o    : out std_ulogic_vector(31 downto 0);  -- CTRL reg
    bgcolor_o : out std_ulogic_vector(31 downto 0);  -- BGCOLOR reg

    -----------------------------------------------------------------
    -- Framebuffer CPU-side port (to helios_framebuffer)
    -----------------------------------------------------------------
    fb_we_o   : out std_ulogic;
    fb_addr_o : out unsigned(FB_ADDR_WIDTH-1 downto 0);
    fb_din_o  : out std_ulogic_vector(FB_BPP-1 downto 0);
    fb_dout_i : in  std_ulogic_vector(FB_BPP-1 downto 0)
  );
end entity helios_vga_xbus;

architecture rtl of helios_vga_xbus is

  -- Simple register map:
  --  base + 0x00 : CTRL    (bit0 = enable)
  --  base + 0x04 : BGCOLOR ([3:0]=R, [7:4]=G, [11:8]=B)
  signal reg_ctrl    : std_ulogic_vector(31 downto 0) := (0 => '1', others => '0');
  signal reg_bgcolor : std_ulogic_vector(31 downto 0) := x"000000F0";

  signal ack_reg   : std_ulogic := '0';
  signal rdata_reg : std_ulogic_vector(31 downto 0) := (others => '0');

  signal fb_we_reg   : std_ulogic := '0';
  signal fb_addr_reg : unsigned(FB_ADDR_WIDTH-1 downto 0) := (others => '0');
  signal fb_din_reg  : std_ulogic_vector(FB_BPP-1 downto 0) := (others => '0');

begin

  -- drive outward
  xbus_dat_o  <= rdata_reg;
  xbus_ack_o  <= ack_reg;
  xbus_err_o  <= '0';  -- no error support yet

  fb_we_o     <= fb_we_reg;
  fb_addr_o   <= fb_addr_reg;
  fb_din_o    <= fb_din_reg;

  ctrl_o      <= reg_ctrl;
  bgcolor_o   <= reg_bgcolor;

  ---------------------------------------------------------------------------
  -- xBUS simple single-cycle slave + VRAM access
  ---------------------------------------------------------------------------
  process(clk_i, rstn_i)
    variable addr_word  : unsigned(3 downto 2);
    variable is_fb_area : boolean;
    variable fb_index   : unsigned(FB_ADDR_WIDTH-1 downto 0);
  begin
    if rstn_i = '0' then
      reg_ctrl    <= (0 => '1', others => '0');
      reg_bgcolor <= x"000000F0";
      ack_reg     <= '0';
      rdata_reg   <= (others => '0');

      fb_we_reg   <= '0';
      fb_addr_reg <= (others => '0');
      fb_din_reg  <= (others => '0');

    elsif rising_edge(clk_i) then
      ack_reg   <= '0';   -- default
      fb_we_reg <= '0';   -- default

      if (xbus_cyc_i = '1') and (xbus_stb_i = '1') and (ack_reg = '0') then

        -- Decide: registers vs VRAM region
        -- Example: offsets with bits[15:12] = VRAM_REGION_SEL -> VRAM
        is_fb_area := (xbus_adr_i(15 downto 12) = VRAM_REGION_SEL);

        if is_fb_area then
          -------------------------------------------------------------------
          -- Framebuffer byte access
          -------------------------------------------------------------------
          -- Simple mapping: use bits [FB_ADDR_WIDTH+1 : 2] as byte index
          fb_index := resize(unsigned(xbus_adr_i(FB_ADDR_WIDTH+1 downto 2)),
                             FB_ADDR_WIDTH);

          fb_addr_reg <= fb_index;

          if xbus_we_i = '1' then
            -- write lowest byte as pixel
            fb_din_reg <= xbus_dat_i(FB_BPP-1 downto 0);
            fb_we_reg  <= '1';
          end if;

          -- readback: place pixel in lowest byte of rdata_reg
          rdata_reg <= (others => '0');
          rdata_reg(FB_BPP-1 downto 0) <= fb_dout_i;

        else
          -------------------------------------------------------------------
          -- Register area (CTRL / BGCOLOR)
          -------------------------------------------------------------------
          addr_word := unsigned(xbus_adr_i(3 downto 2)); -- word index

          if xbus_we_i = '1' then  -- WRITE
            case addr_word is
              when "00" => reg_ctrl    <= xbus_dat_i;   -- 0x00
              when "01" => reg_bgcolor <= xbus_dat_i;   -- 0x04
              when others => null;
            end case;
          else                     -- READ
            case addr_word is
              when "00" => rdata_reg <= reg_ctrl;
              when "01" => rdata_reg <= reg_bgcolor;
              when others => rdata_reg <= (others => '0');
            end case;
          end if;
        end if;

        ack_reg <= '1';
      end if;
    end if;
  end process;

end architecture rtl;
