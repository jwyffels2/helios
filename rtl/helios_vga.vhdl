library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity helios_vga is
  port (
    -- System clock / reset
    clk_i    : in  std_ulogic;
    rstn_i   : in  std_ulogic;  -- active-low

    -- Pixel clock (25 MHz) from top level
    vga_clk_i : in std_logic;

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

    -- VGA pins
    vga_hs  : out std_logic;
    vga_vs  : out std_logic;
    vga_r   : out std_logic_vector(3 downto 0);
    vga_g   : out std_logic_vector(3 downto 0);
    vga_b   : out std_logic_vector(3 downto 0)
  );
end entity helios_vga;

architecture rtl of helios_vga is

  ---------------------------------------------------------------------------
  -- Parameters for framebuffer (320x240 @ 8bpp, upscaled 2x2 to 640x480)
  ---------------------------------------------------------------------------
  constant FB_WIDTH      : natural := 320;
  constant FB_HEIGHT     : natural := 240;
  constant FB_BPP        : natural := 8;
  constant FB_ADDR_WIDTH : natural := 17; -- 2^17 = 131072 > 320*240=76800

  -- XBUS register outputs
  signal reg_ctrl    : std_ulogic_vector(31 downto 0);
  signal reg_bgcolor : std_ulogic_vector(31 downto 0);

  -- Framebuffer CPU-side wires
  signal fb_cpu_we   : std_ulogic;
  signal fb_cpu_addr : unsigned(FB_ADDR_WIDTH-1 downto 0);
  signal fb_cpu_din  : std_ulogic_vector(FB_BPP-1 downto 0);
  signal fb_cpu_dout : std_ulogic_vector(FB_BPP-1 downto 0);

  -- Framebuffer VGA-side wires
  signal fb_vga_addr : unsigned(FB_ADDR_WIDTH-1 downto 0);
  signal fb_vga_dout : std_logic_vector(FB_BPP-1 downto 0);

  -- VGA timer outputs
  signal pix_x      : std_logic_vector(9 downto 0);
  signal pix_y      : std_logic_vector(9 downto 0);
  signal vid_on     : std_logic;
  signal vga_r_int  : std_logic_vector(3 downto 0);
  signal vga_g_int  : std_logic_vector(3 downto 0);
  signal vga_b_int  : std_logic_vector(3 downto 0);

  -- internal upscaled coords
  signal fb_x       : unsigned(8 downto 0);
  signal fb_y       : unsigned(8 downto 0);

begin

  ---------------------------------------------------------------------------
  -- XBUS block (no VGA dependence)
  ---------------------------------------------------------------------------
  u_xbus : entity work.helios_vga_xbus
    generic map (
      FB_ADDR_WIDTH   => FB_ADDR_WIDTH,
      FB_BPP          => FB_BPP,
      VRAM_REGION_SEL => "0001"  -- xbus_adr_i(15..12) = 1xxx -> VRAM
    )
    port map (
      clk_i        => clk_i,
      rstn_i       => rstn_i,

      xbus_adr_i   => xbus_adr_i,
      xbus_dat_i   => xbus_dat_i,
      xbus_dat_o   => xbus_dat_o,
      xbus_we_i    => xbus_we_i,
      xbus_sel_i   => xbus_sel_i,
      xbus_stb_i   => xbus_stb_i,
      xbus_cyc_i   => xbus_cyc_i,
      xbus_ack_o   => xbus_ack_o,
      xbus_err_o   => xbus_err_o,
      xbus_cti_i   => xbus_cti_i,
      xbus_tag_i   => xbus_tag_i,

      ctrl_o       => reg_ctrl,
      bgcolor_o    => reg_bgcolor,

      fb_we_o      => fb_cpu_we,
      fb_addr_o    => fb_cpu_addr,
      fb_din_o     => fb_cpu_din,
      fb_dout_i    => fb_cpu_dout
    );

  ---------------------------------------------------------------------------
  -- Framebuffer RAM
  ---------------------------------------------------------------------------
  u_fb : entity work.helios_framebuffer
    generic map (
      FB_WIDTH   => FB_WIDTH,
      FB_HEIGHT  => FB_HEIGHT,
      BPP        => FB_BPP,
      ADDR_WIDTH => FB_ADDR_WIDTH
    )
    port map (
      clk_cpu   => clk_i,
      we_cpu    => fb_cpu_we,
      addr_cpu  => fb_cpu_addr,
      din_cpu   => fb_cpu_din,
      dout_cpu  => fb_cpu_dout,

      clk_vga   => vga_clk_i,
      addr_vga  => fb_vga_addr,
      dout_vga  => fb_vga_dout
    );

  ---------------------------------------------------------------------------
  -- VGA timing core (your renamed helios_vga_timer)
  ---------------------------------------------------------------------------
  u_vga_timer : entity work.helios_vga_timer
    generic map (
      H_back_porch     => 48,
      H_display        => 640,
      H_front_porch    => 16,
      H_retrace        => 96,
      V_back_porch     => 33,
      V_display        => 480,
      V_front_porch    => 10,
      V_retrace        => 2,
      Color_bits       => 4,
      H_sync_polarity  => '0',
      V_sync_polarity  => '0',
      H_counter_size   => 10,
      V_counter_size   => 10
    )
    port map (
      i_vid_clk     => vga_clk_i,
      i_rstb        => rstn_i, -- active-low

      o_h_sync      => vga_hs,
      o_v_sync      => vga_vs,

      o_pixel_x     => pix_x,
      o_pixel_y     => pix_y,
      o_vid_display => vid_on,

      i_red_in      => vga_r_int,
      i_green_in    => vga_g_int,
      i_blue_in     => vga_b_int,

      o_red_out     => vga_r,
      o_green_out   => vga_g,
      o_blue_out    => vga_b
    );

  ---------------------------------------------------------------------------
  -- VGA side: compute framebuffer address from pixel coords (2x2 upscale)
  ---------------------------------------------------------------------------
  process(vga_clk_i, rstn_i)
    variable ux       : unsigned(8 downto 0);
    variable uy       : unsigned(8 downto 0);
    variable ix, iy   : integer;
    variable addr_int : integer;
  begin
    if rstn_i = '0' then
      fb_vga_addr <= (others => '0');
      fb_x        <= (others => '0');
      fb_y        <= (others => '0');

    elsif rising_edge(vga_clk_i) then
      if vid_on = '1' then
        -- Divide by 2: 640x480 -> 320x240
        ux := unsigned(pix_x(9 downto 1)); -- 0..319
        uy := unsigned(pix_y(9 downto 1)); -- 0..239
        fb_x <= ux;
        fb_y <= uy;

        -- Integer math for address = y*FB_WIDTH + x
        iy       := to_integer(uy);
        ix       := to_integer(ux);
        addr_int := iy * FB_WIDTH + ix;

        fb_vga_addr <= to_unsigned(addr_int, FB_ADDR_WIDTH);
      else
        fb_vga_addr <= (others => '0');
      end if;
    end if;
  end process;


  ---------------------------------------------------------------------------
  -- Color selection:
  --   reg_ctrl(0) = 0 -> video disabled (black)
  --   reg_ctrl(0) = 1, reg_ctrl(1) = 0 -> solid BGCOLOR
  --   reg_ctrl(0) = 1, reg_ctrl(1) = 1 -> framebuffer grayscale
  ---------------------------------------------------------------------------
  process(vid_on, reg_ctrl, reg_bgcolor, fb_vga_dout)
    variable r_nib : std_logic_vector(3 downto 0);
    variable g_nib : std_logic_vector(3 downto 0);
    variable b_nib : std_logic_vector(3 downto 0);
    variable gray  : std_logic_vector(3 downto 0);
  begin
    r_nib := reg_bgcolor(3  downto 0);
    g_nib := reg_bgcolor(7  downto 4);
    b_nib := reg_bgcolor(11 downto 8);

    if (vid_on = '1') and (reg_ctrl(0) = '1') then      -- video enabled
      if reg_ctrl(1) = '1' then -- FRAMEBUFFER MODE
        gray      := fb_vga_dout(7 downto 4);
        vga_r_int <= gray;
        vga_g_int <= gray;
        vga_b_int <= gray;
      else -- BACKGROUND MODE
        vga_r_int <= r_nib;
        vga_g_int <= g_nib;
        vga_b_int <= b_nib;
      end if;
    else  -- disabled / blank
      vga_r_int <= (others => '0');
      vga_g_int <= (others => '0');
      vga_b_int <= (others => '0');
    end if;
  end process;


end architecture rtl;
