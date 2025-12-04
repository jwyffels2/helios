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
    gpio_i      : in std_ulogic_vector(31 downto 0);
    pwm_o       : out std_ulogic_vector(31 downto 0);
    twi_sda_i   : in  STD_ULOGIC;
    twi_sda_o   : out STD_ULOGIC;
    twi_scl_i   : in  STD_ULOGIC;
    twi_scl_o   : out STD_ULOGIC
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

    gpio_core_i <= gpio_i;
    gpio_o           <= gpio_core_o;
    pwm_o            <= pwm_core_o;
    twi_sda_core_i   <= twi_sda_i;
    twi_sda_o        <= twi_sda_core_o;
    twi_scl_core_i   <= twi_scl_i;
    twi_scl_o        <= twi_scl_core_o;


end architecture rtl;
