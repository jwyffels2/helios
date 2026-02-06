library ieee;
use ieee.std_logic_1164.all;

library neorv32;
use neorv32.neorv32_package.all;

entity helios is
  port (
    clk_i       : in  std_ulogic;
    rstn_i      : in  std_ulogic;  -- active-high button on board
    uart0_rxd_i : in  std_ulogic;
    uart0_txd_o : out std_ulogic;
    gpio_o      : out std_ulogic_vector(31 downto 0);
    pwm_o       : out std_ulogic_vector(31 downto 0);

    -- I2C/TWI bus pins must be inout (open-drain)
    twi_sda_io  : inout std_logic;
    twi_scl_io  : inout std_logic
  );
end entity helios;

architecture rtl of helios is

  signal rstn_core   : std_ulogic;

  signal gpio_core_o : std_ulogic_vector(31 downto 0);
  signal gpio_core_i : std_ulogic_vector(31 downto 0);

  signal pwm_core_o  : std_ulogic_vector(31 downto 0);

  -- NEORV32 TWI core-side signals (open-drain "pull low only" outputs)
  signal twi_sda_core_i : std_ulogic;
  signal twi_sda_core_o : std_ulogic;
  signal twi_scl_core_i : std_ulogic;
  signal twi_scl_core_o : std_ulogic;

begin

  -- Reset: convert active-high push button to active-low NEORV32 reset
  rstn_core <= not rstn_i;

  ---------------------------------------------------------------------------
  -- Open-drain / tristate drivers for I2C pins
  -- Drive low only, otherwise release line (Z). External pull-ups required.
  ---------------------------------------------------------------------------
  twi_sda_io    <= '0' when (twi_sda_core_o = '0') else 'Z';
  twi_scl_io    <= '0' when (twi_scl_core_o = '0') else 'Z';

  twi_sda_core_i <= std_ulogic(twi_sda_io); -- sense actual bus level
  twi_scl_core_i <= std_ulogic(twi_scl_io); -- sense actual bus level

  ---------------------------------------------------------------------------
  -- Instantiate NEORV32 SoC top
  ---------------------------------------------------------------------------
  u_neorv32 : entity neorv32.neorv32_top
    generic map (
      CLOCK_FREQUENCY  => 100_000_000,

      IO_GPIO_NUM      => 32,
      IO_UART0_EN      => true,
      IO_UART0_RX_FIFO => 1,
      IO_UART0_TX_FIFO => 1,
      IO_CLINT_EN      => true,
      IO_GPTMR_NUM     => 1,

      BOOT_MODE_SELECT => 0,

      IMEM_EN   => true,
      IMEM_SIZE => 32*1024,
      DMEM_EN   => true,
      DMEM_SIZE => 8*1024,

      RISCV_ISA_C      => true,
      RISCV_ISA_M      => true,
      RISCV_ISA_Zicntr => true,

      IO_PWM_NUM => 1,

      IO_TWI_EN => true
    )
    port map (
      clk_i        => clk_i,
      rstn_i       => rstn_core,
      rstn_ocd_o   => open,
      rstn_wdt_o   => open,

      jtag_tck_i   => '0',
      jtag_tdi_i   => '0',
      jtag_tdo_o   => open,
      jtag_tms_i   => '0',

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

      gpio_o       => gpio_core_o,
      gpio_i       => gpio_core_i,

      uart0_txd_o  => uart0_txd_o,
      uart0_rxd_i  => uart0_rxd_i,
      uart0_rtsn_o => open,
      uart0_ctsn_i => '0',

      uart1_txd_o  => open,
      uart1_rxd_i  => '0',
      uart1_rtsn_o => open,
      uart1_ctsn_i => '0',

      spi_clk_o    => open,
      spi_dat_o    => open,
      spi_dat_i    => '0',
      spi_csn_o    => open,

      sdi_clk_i    => '0',
      sdi_dat_o    => open,
      sdi_dat_i    => '0',
      sdi_csn_i    => '1',

      -- TWI core connection (correct open-drain boundary is above)
      twi_sda_i    => twi_sda_core_i,
      twi_sda_o    => twi_sda_core_o,
      twi_scl_i    => twi_scl_core_i,
      twi_scl_o    => twi_scl_core_o,

      twd_sda_i    => '1',
      twd_sda_o    => open,
      twd_scl_i    => '1',
      twd_scl_o    => open,

      onewire_i    => '1',
      onewire_o    => open,

      pwm_o        => pwm_core_o,

      cfs_in_i     => (others => '0'),
      cfs_out_o    => open,

      neoled_o     => open,

      mtime_time_o => open,

      mtime_irq_i  => '0',
      msw_irq_i    => '0',
      mext_irq_i   => '0'
    );

  -- No external GPIO inputs
  gpio_core_i <= (others => '0');

  -- pass-throughs
  gpio_o <= gpio_core_o;
  pwm_o  <= pwm_core_o;

end architecture rtl;
