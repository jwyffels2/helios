library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
library neorv32;
use neorv32.neorv32_package.all;

-- Wrapper that matches your XDC:
--   clk_i        : 100 MHz clock (W5)
--   rstn_i       : reset button BTNC (active HIGH on board)
--   uart0_rxd_i  : USB-UART RX (B18)
--   uart0_txd_o  : USB-UART TX (A18)
--   gpio_o[7:0]  : LEDs (LD0..LD7)
--
-- Plus: gpio_o(7) is forced to clk_i so you get the clock on a GPIO/LED.

entity helios is
  port (
    clk_i       : in  std_ulogic;
    rstn_i      : in  std_ulogic;  -- active-high button on board
    uart0_rxd_i : in  std_ulogic;
    uart0_txd_o : out std_ulogic;
    gpio_o      : out std_ulogic_vector(31 downto 0);
    pwm_o       : out std_ulogic_vector(31 downto 0);
    twi_sda_i   : in  STD_ULOGIC;
    twi_sda_o   : out STD_ULOGIC;
    twi_scl_i   : in  STD_ULOGIC;
    twi_scl_o   : out STD_ULOGIC;

    vga_hs      : out std_logic;
    vga_vs      : out std_logic;
    vga_r       : out std_logic_vector(3 downto 0);
    vga_g       : out std_logic_vector(3 downto 0);
    vga_b       : out std_logic_vector(3 downto 0)
  );
end entity helios;

architecture rtl of helios is

    -- Internal reset for NEORV32 (active-low)
    signal rstn_core   : std_ulogic;

    -- Internal GPIO between NEORV32 and wrapper
    signal gpio_core_o : std_ulogic_vector(31 downto 0);
    signal gpio_core_i : std_ulogic_vector(31 downto 0);

    -- Internal PWM between NEORV32 and wrapper
    signal pwm_core_o     : STD_ULOGIC_VECTOR(31 downto 0);

    -- Internal TWI Between NEORV32 and wrapper
    signal twi_sda_core_i : STD_ULOGIC;
    signal twi_sda_core_o : STD_ULOGIC;
    signal twi_scl_core_i : STD_ULOGIC;
    signal twi_scl_core_o : STD_ULOGIC;


  -- >>> VGA internal signals <<<
  signal vga_clk    : std_logic; -- will be driven by clock divider for now
  signal pix_x      : std_logic_vector(9 downto 0);
  signal pix_y      : std_logic_vector(9 downto 0);
  signal vid_on     : std_logic;
  signal vga_r_int  : std_logic_vector(3 downto 0);
  signal vga_g_int  : std_logic_vector(3 downto 0);
  signal vga_b_int  : std_logic_vector(3 downto 0);

  -- simple /4 divider from 100 MHz to ~25 MHz
  signal vga_div_cnt : unsigned(1 downto 0) := (others => '0');

begin

  ---------------------------------------------------------------------------
  -- Reset: convert active-high push button to active-low NEORV32 reset
  ---------------------------------------------------------------------------
  rstn_core <= not rstn_i;

  ---------------------------------------------------------------------------
  -- Instantiate NEORV32 SoC top
  ---------------------------------------------------------------------------
  u_neorv32 : entity neorv32.neorv32_top
    generic map (
      -- Basys3 clock is 100 MHz
      CLOCK_FREQUENCY  => 100_000_000,

      -- Enable GPIO and UART0 as used by your XDC
      IO_GPIO_NUM      => 32,
      IO_UART0_EN      => true,
      IO_UART0_RX_FIFO => 1,
      IO_UART0_TX_FIFO => 1,
      IO_CLINT_EN      => true,

      IO_GPTMR_NUM      => 1,

      -- Boot configuration: force internal UART bootloader
      BOOT_MODE_SELECT => 0,

      -- Instruction/Data memories
      IMEM_EN   => true,
      IMEM_SIZE => 32*1024, -- or 64*1024, etc.
      DMEM_EN   => true,
      DMEM_SIZE => 8*1024,

      -- CPU extensions (optional but nice to match your old setup)
      RISCV_ISA_C      => true,
      RISCV_ISA_M      => true,
      RISCV_ISA_Zicntr => true,

      -- Enable PWM and ENABLE precisely one PWM Channel
      IO_PWM_NUM => 1,

      -- Enable TWI

      IO_TWI_EN => true

      -- All other generics use defaults

    )
    port map (
      -- Global control
      clk_i        => clk_i,
      rstn_i       => rstn_core,
      rstn_ocd_o   => open,
      rstn_wdt_o   => open,

      -- JTAG OCD (unused here)
      jtag_tck_i   => '0',
      jtag_tdi_i   => '0',
      jtag_tdo_o   => open,
      jtag_tms_i   => '0',

      -- External bus (unused)
      xbus_adr_o   => open,
      xbus_dat_o   => open,
      xbus_cti_o   => open,
      xbus_tag_o   => open,
      xbus_we_o    => open,
      xbus_sel_o   => open,
      xbus_stb_o   => open,
      xbus_cyc_o   => open,
      xbus_dat_i   => (others => '0'),
      xbus_ack_i   => '0',
      xbus_err_i   => '0',

      -- SLINK (unused)
      slink_rx_dat_i => (others => '0'),
      slink_rx_src_i => (others => '0'),
      slink_rx_val_i => '0',
      slink_rx_lst_i => '0',
      slink_rx_rdy_o => open,
      slink_tx_dat_o => open,
      slink_tx_dst_o => open,
      slink_tx_val_o => open,
      slink_tx_lst_o => open,
      slink_tx_rdy_i => '0',

      -- GPIO
      gpio_o       => gpio_core_o,
      gpio_i       => gpio_core_i,

      -- UART0 (mapped to USB-UART on Basys3)
      uart0_txd_o  => uart0_txd_o,
      uart0_rxd_i  => uart0_rxd_i,
      uart0_rtsn_o => open,
      uart0_ctsn_i => '0',

      -- UART1 (unused)
      uart1_txd_o  => open,
      uart1_rxd_i  => '0',
      uart1_rtsn_o => open,
      uart1_ctsn_i => '0',

      -- SPI (unused)
      spi_clk_o    => open,
      spi_dat_o    => open,
      spi_dat_i    => '0',
      spi_csn_o    => open,

      -- SDI (unused)
      sdi_clk_i    => '0',
      sdi_dat_o    => open,
      sdi_dat_i    => '0',
      sdi_csn_i    => '1',

      -- TWI used for camera communication
      twi_sda_i    => twi_sda_core_i,
      twi_sda_o    => twi_sda_core_o,
      twi_scl_i    => twi_scl_core_i,
      twi_scl_o    => twi_scl_core_o,

      -- TWD (unused)
      twd_sda_i    => '1',
      twd_sda_o    => open,
      twd_scl_i    => '1',
      twd_scl_o    => open,

      -- 1-Wire (unused)
      onewire_i    => '1',
      onewire_o    => open,

      -- PWM (used externally)
      pwm_o => pwm_core_o,

      -- CFS (unused)
      cfs_in_i     => (others => '0'),
      cfs_out_o    => open,

      -- NeoPixel (unused)
      neoled_o     => open,

      -- CLINT time (unused externally)
      mtime_time_o => open,

      -- External IRQs (none for now)
      mtime_irq_i  => '0',
      msw_irq_i    => '0',
      mext_irq_i   => '0'
    );


  -- No external GPIO inputs
    gpio_core_i <= (others => '0');

    --gpio_o           <= gpio_core_o;
    pwm_o            <= pwm_core_o;
    twi_sda_core_i   <= twi_sda_i;
    twi_sda_o        <= twi_sda_core_o;
    twi_scl_core_i   <= twi_scl_i;
    twi_scl_o        <= twi_scl_core_o;


  ---------------------------------------------------------------------------
  -- >>> VGA: use PWM(0) as pixel clock <<<
  ---------------------------------------------------------------------------
  -- vga_clk <= std_logic(pwm_core_o(0));  -- PWM(0) drives helios_vga clock

  ---------------------------------------------------------------------------
  -- >>> VGA: temporary clock divider from 100 MHz (for debug) <<<
  ---------------------------------------------------------------------------
  process(clk_i, rstn_core)
  begin
    if rstn_core = '0' then
      vga_div_cnt <= (others => '0');
      vga_clk     <= '0';
    elsif rising_edge(clk_i) then
      vga_div_cnt <= vga_div_cnt + 1;
      vga_clk     <= vga_div_cnt(1);  -- 100 MHz / 4 = 25 MHz
    end if;
  end process;

  -- VGA timing core (helios_vga)
  u_vga : entity work.helios_vga
    generic map (
      -- 640x480@60 timing
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
      i_vid_clk     => vga_clk,
      i_rstb        => rstn_core, -- active-low reset

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
  -- Simple test pattern (combinational) so you can SEE something
  ---------------------------------------------------------------------------
  process(pix_x, pix_y, vid_on)
  begin
    if vid_on = '1' then
      -- crude vertical color bars based on X
      vga_r_int <= (others => pix_x(5));  -- red in some columns
      vga_g_int <= (others => pix_x(6));  -- green in others
      vga_b_int <= (others => pix_x(7));  -- blue in others
    else
      vga_r_int <= (others => '0');
      vga_g_int <= (others => '0');
      vga_b_int <= (others => '0');
    end if;
  end process;
-- Debug: mirror HS/VS to LEDs (gpio_o[0] = HS, gpio_o[1] = VS)
    gpio_o <= (31 downto 2 => '0', 1 => vga_vs, 0 => vga_hs);
end architecture rtl;
