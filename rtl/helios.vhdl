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

    gpio_o      : out std_ulogic_vector(31 downto 0);
    pwm_o       : out std_ulogic_vector(31 downto 0);

    -- VGA physical outputs
    vga_hsync_o : out std_ulogic;
    vga_vsync_o : out std_ulogic;
    vga_r_o     : out std_ulogic_vector(3 downto 0);
    vga_g_o     : out std_ulogic_vector(3 downto 0);
    vga_b_o     : out std_ulogic_vector(3 downto 0)
  );
end entity helios;

architecture rtl of helios is

    signal rstn_core   : std_ulogic;

  signal gpio_core_o : std_ulogic_vector(31 downto 0);
  signal gpio_core_i : std_ulogic_vector(31 downto 0);

  -- NEORV32 PWM is 16-bit wide in your version
  signal pwm_core_o  : std_ulogic_vector(15 downto 0);

  -- 2-bit divider: 100 MHz -> 25 MHz
  signal pixclk_div  : unsigned(1 downto 0) := (others => '0');
  signal pixclk_25   : std_ulogic := '0';

  -- VGA internal nets (from your stub module)
  signal vga_hs : std_ulogic;
  signal vga_vs : std_ulogic;
  signal vga_r  : std_ulogic_vector(3 downto 0);
  signal vga_g  : std_ulogic_vector(3 downto 0);
  signal vga_b  : std_ulogic_vector(3 downto 0);

  -- future CPU write interface (stubbed for now)
  signal fb_we   : std_ulogic := '0';
  signal fb_addr : std_ulogic_vector(15 downto 0) := (others => '0');
  signal fb_data : std_ulogic_vector(7 downto 0)  := (others => '0');

begin

  ---------------------------------------------------------------------------
  -- Reset conversion
  ---------------------------------------------------------------------------
   rstn_core <= not rstn_i; -- press button => rstn_i=1 => rstn_core=0 (reset asserted)

  ---------------------------------------------------------------------------
  -- NEORV32 SoC
  ---------------------------------------------------------------------------
  u_neorv32 : entity neorv32.neorv32_top
    generic map (
      CLOCK_FREQUENCY  => 100_000_000,
      IO_GPIO_NUM      => 32,
      IO_UART0_EN      => true,
      IO_UART0_RX_FIFO => 1,
      IO_UART0_TX_FIFO => 1,
      IO_CLINT_EN      => true,
      BOOT_MODE_SELECT => 0,
      IMEM_EN          => true,
      IMEM_SIZE        => 32*1024,
      DMEM_EN          => true,
      DMEM_SIZE        => 8*1024,
      RISCV_ISA_C      => true,
      RISCV_ISA_M      => true,
      RISCV_ISA_Zicntr => true,
      IO_PWM_NUM_CH    => 1
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

      twi_sda_i    => '1',
      twi_sda_o    => open,
      twi_scl_i    => '1',
      twi_scl_o    => open,

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
   -- Pixel clock divider (100 MHz -> 25 MHz)
  process(clk_i)
  begin
    if rising_edge(clk_i) then
      if (rstn_core = '0') then
        pixclk_div <= (others => '0');
      else
        pixclk_div <= pixclk_div + 1;
      end if;
    end if;
  end process;

  pixclk_25 <= std_ulogic(pixclk_div(1));
  ---------------------------------------------------------------------------
  -- VGA framebuffer integration (stub)
  ---------------------------------------------------------------------------
  u_vga_fb : entity work.vga_fb_integration_stub
    port map (
      clk_i     => pixclk_25,

      -- Choose one reset convention and be consistent:
      -- If stub expects active-high reset:
      rst_i     => not rstn_core,

      hsync_o   => vga_hs,
      vsync_o   => vga_vs,
      r_o       => vga_r,
      g_o       => vga_g,
      b_o       => vga_b,

      fb_we_i   => fb_we,
      fb_addr_i => fb_addr,
      fb_data_i => fb_data
    );
  ---------------------------------------------------------------------------
  -- Output wiring
  ---------------------------------------------------------------------------
  gpio_core_i <= (others => '0');

  gpio_o <= gpio_core_o;
  pwm_o <= (31 downto 16 => '0') & pwm_core_o;

  vga_hsync_o <= vga_hs;
  vga_vsync_o <= vga_vs;
  vga_r_o     <= vga_r;
  vga_g_o     <= vga_g;
  vga_b_o     <= vga_b;

end architecture rtl;
