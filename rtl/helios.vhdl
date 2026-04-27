library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library neorv32;
use neorv32.neorv32_package.all;

-- Basys3 top-level wrapper for the NEORV32 system.
--
-- This file is the hardware integration point. The CPU owns normal peripherals
-- such as UART, GPIO, PWM, and TWI. The framebuffer is attached separately on
-- the NEORV32 external bus (XBUS), then scanned continuously by VGA logic.
entity helios is
   port (
      clk_i       : in    std_ulogic;
      rstn_i      : in    std_ulogic;  -- active-high push button on board
      uart0_rxd_i : in    std_ulogic;
      uart0_txd_o : out   std_ulogic;
      uart1_rxd_i : in    std_ulogic;
      uart1_txd_o : out   std_ulogic;
      gpio_o      : out   std_ulogic_vector(31 downto 0);
      pwm_o       : out   std_ulogic_vector(31 downto 0);
      twi_sda_io  : inout std_logic;
      twi_scl_io  : inout std_logic;
      vga_hsync_o : out   std_ulogic;
      vga_vsync_o : out   std_ulogic;
      vga_r_o     : out   std_ulogic_vector(3 downto 0);
      vga_g_o     : out   std_ulogic_vector(3 downto 0);
      vga_b_o     : out   std_ulogic_vector(3 downto 0)
   );
end entity helios;

architecture rtl of helios is

   signal rstn_core : std_ulogic;

   signal gpio_core_o : std_ulogic_vector(31 downto 0);
   signal gpio_core_i : std_ulogic_vector(31 downto 0);

   signal pwm_core_o : std_ulogic_vector(31 downto 0);

   signal twi_sda_core_i : std_ulogic;
   signal twi_sda_core_o : std_ulogic;
   signal twi_scl_core_i : std_ulogic;
   signal twi_scl_core_o : std_ulogic;

   -- NEORV32 XBUS signals. The CPU uses this bus to write RGB332 pixels into
   -- the framebuffer MMIO window at 0xF0000000.
   signal xbus_adr   : std_ulogic_vector(31 downto 0);
   signal xbus_dat_o : std_ulogic_vector(31 downto 0);
   signal xbus_we    : std_ulogic;
   signal xbus_sel   : std_ulogic_vector(3 downto 0);
   signal xbus_stb   : std_ulogic;
   signal xbus_cyc   : std_ulogic;

   signal xbus_dat_i : std_ulogic_vector(31 downto 0);
   signal xbus_ack   : std_ulogic;
   signal xbus_err   : std_ulogic := '0';

   -- Narrowed framebuffer write interface produced by the XBUS slave. The VRAM
   -- block accepts these writes while VGA reads from a separate scanout port.
   signal vram_cpu_we    : std_ulogic;
   signal vram_cpu_be    : std_ulogic_vector(3 downto 0);
   signal vram_cpu_addr  : unsigned(31 downto 0);
   signal vram_cpu_wdata : std_ulogic_vector(31 downto 0);
   signal vram_ready     : std_ulogic;

   signal vga_addr  : unsigned(14 downto 0);
   signal vga_pixel : std_ulogic_vector(7 downto 0);

begin

   -- The Basys3 push button is active high, while NEORV32 expects active-low
   -- reset, so invert once at the board boundary.
   rstn_core <= not rstn_i;

   -- Model the TWI pins as open-drain outputs: drive low for zero, otherwise
   -- release the external pull-up.
   twi_sda_io <= '0' when twi_sda_core_o = '0' else 'Z';
   twi_scl_io <= '0' when twi_scl_core_o = '0' else 'Z';

   twi_sda_core_i <= std_ulogic(twi_sda_io);
   twi_scl_core_i <= std_ulogic(twi_scl_io);

   u_neorv32 : entity neorv32.neorv32_top
      generic map (
         CLOCK_FREQUENCY  => 100_000_000,
         IO_GPIO_NUM      => 32,
         IO_UART0_EN      => true,
         IO_UART0_RX_FIFO => 1,
         IO_UART0_TX_FIFO => 1,
         IO_UART1_EN      => true,
         IO_UART1_RX_FIFO => 1,
         IO_UART1_TX_FIFO => 1,
         IO_CLINT_EN      => true,
         IO_GPTMR_NUM     => 1,
         BOOT_MODE_SELECT => 0,
         IMEM_EN          => true,
         IMEM_SIZE        => 32 * 1024,
         DMEM_EN          => true,
         DMEM_SIZE        => 128 * 1024,
         RISCV_ISA_C      => true,
         RISCV_ISA_M      => true,
         RISCV_ISA_Zicntr => true,
         IO_PWM_NUM       => 1,
         IO_TWI_EN        => true,
         XBUS_EN          => true
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

         -- External bus master side. Only the framebuffer slave responds to
         -- this window in this design.
         xbus_adr_o   => xbus_adr,
         xbus_dat_o   => xbus_dat_o,
         xbus_cti_o   => open,
         xbus_tag_o   => open,
         xbus_we_o    => xbus_we,
         xbus_sel_o   => xbus_sel,
         xbus_stb_o   => xbus_stb,
         xbus_cyc_o   => xbus_cyc,
         xbus_dat_i   => xbus_dat_i,
         xbus_ack_i   => xbus_ack,
         xbus_err_i   => xbus_err,

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

         -- UART1 is kept separate from the boot/debug UART so camera/comms
         -- traffic does not interfere with the console.
         uart1_txd_o  => uart1_txd_o,
         uart1_rxd_i  => uart1_rxd_i,
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

   -- Decode CPU writes in the framebuffer address range and translate the
   -- 32-bit XBUS transaction into byte enables for the RGB332 VRAM.
   u_vram_xbus : entity work.vram_xbus_slave
      generic map (
         BASE_ADDR => x"F0000000",
         WIN_SIZE  => x"00005000"
      )
      port map (
         clk_i => clk_i,
         rstn_i => rstn_core,

         xbus_cyc_i => xbus_cyc,
         xbus_stb_i => xbus_stb,
         xbus_we_i  => xbus_we,
         xbus_adr_i => xbus_adr,
         xbus_dat_i => xbus_dat_o,
         xbus_sel_i => xbus_sel,

         xbus_ack_o => xbus_ack,
         xbus_dat_o => xbus_dat_i,

         vram_ready_i => vram_ready,
         cpu_we_o     => vram_cpu_we,
         cpu_be_o     => vram_cpu_be,
         cpu_addr_o   => vram_cpu_addr,
         cpu_wdata_o  => vram_cpu_wdata
      );

   -- Dual-port framebuffer storage. Software writes through the CPU side, and
   -- VGA scanout reads pixels every display tick from the independent read side.
   u_vram : entity work.vram_rgb332_dp
      generic map (
         FB_SIZE => 19200
      )
      port map (
         clk_i => clk_i,
         rstn_i => rstn_core,

         cpu_we_i    => vram_cpu_we,
         cpu_be_i    => vram_cpu_be,
         cpu_addr_i  => vram_cpu_addr,
         cpu_wdata_i => vram_cpu_wdata,
         cpu_ready_o => vram_ready,

         vga_addr_i  => vga_addr,
         vga_rdata_o => vga_pixel
      );

   -- VGA never asks the CPU for pixels. It continuously walks the framebuffer,
   -- scales the 160x120 image to 640x480, and drives the monitor pins.
   u_vga_scanout : entity work.vga_scanout_rgb332
      generic map (
         FB_WIDTH   => 160,
         FB_HEIGHT  => 120,
         PIX_CE_DIV => 4
      )
      port map (
         clk_i        => clk_i,
         rstn_i       => rstn_core,
         vram_addr_o  => vga_addr,
         vram_rdata_i => vga_pixel,
         vga_hsync_o  => vga_hsync_o,
         vga_vsync_o  => vga_vsync_o,
         vga_r_o      => vga_r_o,
         vga_g_o      => vga_g_o,
         vga_b_o      => vga_b_o
      );

   gpio_core_i <= (others => '0');

   gpio_o <= gpio_core_o;
   pwm_o  <= pwm_core_o;

end architecture rtl;
