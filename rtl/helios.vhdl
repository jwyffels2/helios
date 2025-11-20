library ieee;
use ieee.std_logic_1164.all;

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
    cam_clk_o   : out std_ulogic  -- dedicated 24MHz clock
  );
end entity helios;

architecture rtl of helios is

  -- Internal reset for NEORV32 (active-low)
  signal rstn_core   : std_ulogic;

  -- Internal GPIO between NEORV32 and wrapper
  signal gpio_core_o : std_ulogic_vector(31 downto 0);
  signal gpio_core_i : std_ulogic_vector(31 downto 0);

  -- Local copy of core GPIO output so we can override one bit
  signal gpio_o_int  : std_ulogic_vector(31 downto 0);

  -- Camera Mapping

  signal cam_clk_24   : std_logic;
  signal cam_clk_lock : std_logic;

  component cam_clk
    port (
      clk_out : out std_logic;
      reset   : in  std_logic;
      locked  : out std_logic;
      clk_in  : in  std_logic
    );
  end component;

begin

  ---------------------------------------------------------------------------
  -- Reset: convert active-high push button to active-low NEORV32 reset
  ---------------------------------------------------------------------------
  rstn_core <= not rstn_i;

  ---------------------------------------------------------------------------
  -- Add Camera
  ---------------------------------------------------------------------------
  u_cam_clk : cam_clk
    port map (
      clk_out => cam_clk_24,
      reset   => not rstn_core, -- active-high reset
      locked  => cam_clk_lock,
      clk_in  => clk_i
    );

  cam_clk_o <= cam_clk_24;

  ---------------------------------------------------------------------------
  -- Instantiate NEORV32 SoC top (unmodified neorv32_top)
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


      IO_GPTMR_EN      => true,

    -- Boot configuration: force internal UART bootloader
    BOOT_MODE_SELECT => 0,

    -- Instruction/Data memories
    IMEM_EN          => true,
    IMEM_SIZE        => 16*1024,
    DMEM_EN          => true,
    DMEM_SIZE        => 8*1024,

    -- CPU extensions (optional but nice to match your old setup)
    RISCV_ISA_C      => true,
    RISCV_ISA_M      => true,
    RISCV_ISA_Zicntr => true

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

      -- TWI (unused)
      twi_sda_i    => '1',
      twi_sda_o    => open,
      twi_scl_i    => '1',
      twi_scl_o    => open,

      -- TWD (unused)
      twd_sda_i    => '1',
      twd_sda_o    => open,
      twd_scl_i    => '1',
      twd_scl_o    => open,

      -- 1-Wire (unused)
      onewire_i    => '1',
      onewire_o    => open,

      -- PWM (unused externally)
      pwm_o        => open,

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

  -- Directly expose core GPIOs
  gpio_o <= gpio_core_o;

end architecture rtl;
