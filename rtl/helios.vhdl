library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library neorv32;
use neorv32.neorv32_package.all;

entity helios is
  port (
    clk_i       : in  std_ulogic;
    rstn_i      : in  std_ulogic;  -- active-high button on board
    uart0_rxd_i : in  std_ulogic;
    uart0_txd_o : out std_ulogic;

    -- only 12 GPIO outputs now
    gpio_o      : out std_ulogic_vector(11 downto 0);

    -- only 1 PWM output
    pwm_o       : out std_ulogic;

    twi_sda     : inout std_logic;
    twi_scl     : inout std_logic;

    -- VGA outputs
    vga_hs      : out std_logic;
    vga_vs      : out std_logic;
    vga_r       : out std_logic_vector(3 downto 0);
    vga_g       : out std_logic_vector(3 downto 0);
    vga_b       : out std_logic_vector(3 downto 0)
  );
end entity helios;

architecture rtl of helios is

  ---------------------------------------------------------------------------
  -- Internal reset for NEORV32 (active-low)
  ---------------------------------------------------------------------------
  signal rstn_core   : std_ulogic;

  ---------------------------------------------------------------------------
  -- Internal GPIO between NEORV32 and wrapper
  ---------------------------------------------------------------------------
  signal gpio_core_o : std_ulogic_vector(31 downto 0);
  signal gpio_core_i : std_ulogic_vector(31 downto 0);

  ---------------------------------------------------------------------------
  -- Internal PWM between NEORV32 and wrapper
  ---------------------------------------------------------------------------
  signal pwm_core_o  : std_ulogic_vector(31 downto 0);

  ---------------------------------------------------------------------------
  -- Internal TWI Between NEORV32 and wrapper
  ---------------------------------------------------------------------------
  signal twi_sda_core_i : std_ulogic;
  signal twi_sda_core_o : std_ulogic;
  signal twi_scl_core_i : std_ulogic;
  signal twi_scl_core_o : std_ulogic;

  ---------------------------------------------------------------------------
  -- External bus (xbus) signals: NEORV32 master -> VGA xbus slave
  ---------------------------------------------------------------------------
  signal xbus_adr    : std_ulogic_vector(31 downto 0);
  signal xbus_dat_m2s: std_ulogic_vector(31 downto 0); -- master -> slave
  signal xbus_dat_s2m: std_ulogic_vector(31 downto 0); -- slave -> master
  signal xbus_cti    : std_ulogic_vector(2 downto 0);
  signal xbus_tag    : std_ulogic_vector(2 downto 0);
  signal xbus_we     : std_ulogic;
  signal xbus_sel    : std_ulogic_vector(3 downto 0);
  signal xbus_stb    : std_ulogic;
  signal xbus_cyc    : std_ulogic;
  signal xbus_ack    : std_ulogic;
  signal xbus_err    : std_ulogic;

  ---------------------------------------------------------------------------
  -- VGA pixel clock divider: 100 MHz -> 25 MHz
  ---------------------------------------------------------------------------
  signal vga_clk     : std_logic;
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
      -- Board clock is 100 MHz
      CLOCK_FREQUENCY  => 100_000_000,

      -- Peripherals
      IO_GPIO_NUM      => 32,
      IO_UART0_EN      => true,
      IO_UART0_RX_FIFO => 1,
      IO_UART0_TX_FIFO => 1,
      IO_CLINT_EN      => true,

      IO_GPTMR_NUM     => 1,

      -- Boot configuration: internal UART bootloader
      BOOT_MODE_SELECT => 0,

      -- Instruction/Data memories
      IMEM_EN          => true,
      IMEM_SIZE        => 64*1024,
      DMEM_EN          => true,
      DMEM_SIZE        => 8*1024,

      -- CPU extensions
      RISCV_ISA_C      => true,
      RISCV_ISA_M      => true,
      RISCV_ISA_Zicntr => true,

      -- PWM
      IO_PWM_NUM       => 1,

      -- TWI
      IO_TWI_EN        => true,

      -- XBUS
      XBUS_EN          => true,
      XBUS_TIMEOUT     => 16

      -- Other generics default
    )
    port map (
      -- Global control
      clk_i        => clk_i,
      rstn_i       => rstn_core,
      rstn_ocd_o   => open,
      rstn_wdt_o   => open,

      -- JTAG OCD (unused)
      jtag_tck_i   => '0',
      jtag_tdi_i   => '0',
      jtag_tdo_o   => open,
      jtag_tms_i   => '0',

      -- External bus (xbus) - now CONNECTED to VGA
      xbus_adr_o   => xbus_adr,
      xbus_dat_o   => xbus_dat_m2s,
      xbus_cti_o   => xbus_cti,
      xbus_tag_o   => xbus_tag,
      xbus_we_o    => xbus_we,
      xbus_sel_o   => xbus_sel,
      xbus_stb_o   => xbus_stb,
      xbus_cyc_o   => xbus_cyc,
      xbus_dat_i   => xbus_dat_s2m,
      xbus_ack_i   => xbus_ack,
      xbus_err_i   => xbus_err,

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

      -- UART0
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

      -- TWI used externally
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

      -- PWM
      pwm_o        => pwm_core_o,

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

  ---------------------------------------------------------------------------
  -- VGA pixel clock: 100 MHz / 4 = 25 MHz
  ---------------------------------------------------------------------------
  process(clk_i, rstn_core)
  begin
    if rstn_core = '0' then
      vga_div_cnt <= (others => '0');
      vga_clk     <= '0';
    elsif rising_edge(clk_i) then
      vga_div_cnt <= vga_div_cnt + 1;
      vga_clk     <= std_logic(vga_div_cnt(1));
    end if;
  end process;

  ---------------------------------------------------------------------------
  -- Instantiate VGA xbus peripheral (wraps helios_vga)
  ---------------------------------------------------------------------------
  u_vga_xbus : entity work.helios_vga_xbus
    port map (
      clk_i      => clk_i,
      rstn_i     => rstn_core,

      vga_clk_i  => vga_clk,

      xbus_adr_i => xbus_adr,
      xbus_dat_i => xbus_dat_m2s,
      xbus_dat_o => xbus_dat_s2m,
      xbus_we_i  => xbus_we,
      xbus_sel_i => xbus_sel,
      xbus_stb_i => xbus_stb,
      xbus_cyc_i => xbus_cyc,
      xbus_ack_o => xbus_ack,
      xbus_err_o => xbus_err,
      xbus_cti_i => xbus_cti,
      xbus_tag_i => xbus_tag,

      vga_hs     => vga_hs,
      vga_vs     => vga_vs,
      vga_r      => vga_r,
      vga_g      => vga_g,
      vga_b      => vga_b
    );

  ---------------------------------------------------------------------------
  -- GPIO, PWM, TWI wiring to top-level ports
  ---------------------------------------------------------------------------
    -- No external GPIO inputs: feed zeros into NEORV32
    gpio_core_i <= (others => '0');

    -- Only expose lower 12 GPIO outputs to pins
    gpio_o <= gpio_core_o(11 downto 0);

    -- Only expose PWM channel 0
    pwm_o <= pwm_core_o(0);

  -- SDA Open-Drain Wiring
  twi_sda           <= '0' when (twi_sda_core_o = '0') else 'Z';
  twi_sda_core_i    <= twi_sda;

  -- SCL Open-Drain Wiring
  twi_scl           <= '0' when (twi_scl_core_o = '0') else 'Z';
  twi_scl_core_i    <= twi_scl;

end architecture rtl;
