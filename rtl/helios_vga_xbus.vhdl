library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity helios_vga_xbus is
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
end entity helios_vga_xbus;

architecture rtl of helios_vga_xbus is

  -- Simple register map:
  --  base + 0x00 : CTRL    (bit0 = enable)
  --  base + 0x04 : BGCOLOR ([3:0]=R, [7:4]=G, [11:8]=B)
  signal reg_ctrl    : std_ulogic_vector(31 downto 0) := (others => '0');
  signal reg_bgcolor : std_ulogic_vector(31 downto 0) := (others => '0');

  signal ack_reg   : std_ulogic := '0';
  signal rdata_reg : std_ulogic_vector(31 downto 0) := (others => '0');

  -- VGA core signals
  signal pix_x      : std_logic_vector(9 downto 0);
  signal pix_y      : std_logic_vector(9 downto 0);
  signal vid_on     : std_logic;
  signal vga_r_int  : std_logic_vector(3 downto 0);
  signal vga_g_int  : std_logic_vector(3 downto 0);
  signal vga_b_int  : std_logic_vector(3 downto 0);

begin

  ---------------------------------------------------------------------------
  -- xBUS simple single-cycle slave
  ---------------------------------------------------------------------------
  process(clk_i, rstn_i)
    variable addr_word : unsigned(3 downto 2);
  begin
    if rstn_i = '0' then
      reg_ctrl    <= (others => '0');
      reg_bgcolor <= (others => '0');
      ack_reg     <= '0';
      rdata_reg   <= (others => '0');

    elsif rising_edge(clk_i) then
      ack_reg <= '0'; -- default

      if (xbus_cyc_i = '1') and (xbus_stb_i = '1') and (ack_reg = '0') then
        addr_word := unsigned(xbus_adr_i(3 downto 2)); -- word address

        if xbus_we_i = '1' then  -- WRITE
          case addr_word is
            when "00" => reg_ctrl    <= xbus_dat_i;   -- 0x00
            when "01" => reg_bgcolor <= xbus_dat_i;   -- 0x04
            when others => null;
          end case;
        else                    -- READ
          case addr_word is
            when "00" => rdata_reg <= reg_ctrl;
            when "01" => rdata_reg <= reg_bgcolor;
            when others => rdata_reg <= (others => '0');
          end case;
        end if;

        ack_reg <= '1';
      end if;
    end if;
  end process;

  xbus_dat_o <= rdata_reg;
  xbus_ack_o <= ack_reg;
  xbus_err_o <= '0';   -- no error support yet (always OK)

  ---------------------------------------------------------------------------
  -- Instantiate existing timing core
  ---------------------------------------------------------------------------
  u_vga : entity work.helios_vga
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
  -- Solid background color based on BGCOLOR register
  ---------------------------------------------------------------------------
  process(pix_x, pix_y, vid_on, reg_ctrl, reg_bgcolor)
    variable r_nib : std_logic_vector(3 downto 0);
    variable g_nib : std_logic_vector(3 downto 0);
    variable b_nib : std_logic_vector(3 downto 0);
  begin
    r_nib := reg_bgcolor(3  downto 0);
    g_nib := reg_bgcolor(7  downto 4);
    b_nib := reg_bgcolor(11 downto 8);

    if (reg_ctrl(0) = '1') and (vid_on = '1') then
      vga_r_int <= r_nib;
      vga_g_int <= g_nib;
      vga_b_int <= b_nib;
    else
      vga_r_int <= (others => '0');
      vga_g_int <= (others => '0');
      vga_b_int <= (others => '0');
    end if;
  end process;

end architecture rtl;
