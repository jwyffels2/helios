-- ================================================================================ --
-- NEORV32 - Processor Top Entity with AvalonMM Compatible Host Interface           --
-- -------------------------------------------------------------------------------- --
-- The NEORV32 RISC-V Processor - https://github.com/stnolting/neorv32              --
-- Copyright (c) NEORV32 contributors.                                              --
-- Copyright (c) 2020 - 2024 Stephan Nolting. All rights reserved.                  --
-- Licensed under the BSD-3-Clause license, see LICENSE for details.                --
-- SPDX-License-Identifier: BSD-3-Clause                                            --
-- ================================================================================ --

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library neorv32;
use neorv32.neorv32_package.all;

entity neorv32_top_avalonmm is
  generic (
    -- General --
    CLOCK_FREQUENCY              : natural;           -- clock frequency of clk_i in Hz
    HART_ID                      : std_ulogic_vector(31 downto 0) := x"00000000"; -- hardware thread ID
    JEDEC_ID                     : std_ulogic_vector(10 downto 0) := "00000000000"; -- JEDEC ID: continuation codes + vendor ID
    INT_BOOTLOADER_EN            : boolean := false;  -- boot configuration: true = boot explicit bootloader; false = boot from int/ext (I)MEM

    -- On-Chip Debugger (OCD) --
    ON_CHIP_DEBUGGER_EN          : boolean := false;  -- implement on-chip debugger

    -- RISC-V CPU Extensions --
    CPU_EXTENSION_RISCV_B        : boolean := false;  -- implement bit-manipulation extension?
    CPU_EXTENSION_RISCV_C        : boolean := false;  -- implement compressed extension?
    CPU_EXTENSION_RISCV_E        : boolean := false;  -- implement embedded RF extension?
    CPU_EXTENSION_RISCV_M        : boolean := false;  -- implement mul/div extension?
    CPU_EXTENSION_RISCV_U        : boolean := false;  -- implement user mode extension?
    CPU_EXTENSION_RISCV_Zfinx    : boolean := false;  -- implement 32-bit floating-point extension (using INT regs!)
    CPU_EXTENSION_RISCV_Zicntr   : boolean := true;   -- implement base counters?
    CPU_EXTENSION_RISCV_Zihpm    : boolean := false;  -- implement hardware performance monitors?
    CPU_EXTENSION_RISCV_Zmmul    : boolean := false;  -- implement multiply-only M sub-extension?
    CPU_EXTENSION_RISCV_Zxcfu    : boolean := false;  -- implement custom (instr.) functions unit?

    -- Extension Options --
    FAST_MUL_EN                  : boolean := false;  -- use DSPs for M extension's multiplier
    FAST_SHIFT_EN                : boolean := false;  -- use barrel shifter for shift operations

    -- Physical Memory Protection (PMP) --
    PMP_NUM_REGIONS              : natural := 0;      -- number of regions (0..16)
    PMP_MIN_GRANULARITY          : natural := 4;      -- minimal region granularity in bytes, has to be a power of 2, min 4 bytes

    -- Hardware Performance Monitors (HPM) --
    HPM_NUM_CNTS                 : natural := 0;      -- number of implemented HPM counters (0..29)
    HPM_CNT_WIDTH                : natural := 40;     -- total size of HPM counters (0..64)

    -- Internal Instruction memory (IMEM) --
    IMEM_EN              : boolean := false;  -- implement processor-internal instruction memory
    IMEM_SIZE            : natural := 16*1024; -- size of processor-internal instruction memory in bytes

    -- Internal Data memory (DMEM) --
    DMEM_EN              : boolean := false;  -- implement processor-internal data memory
    DMEM_SIZE            : natural := 8*1024; -- size of processor-internal data memory in bytes

    -- Internal Cache memory (iCACHE) --
    ICACHE_EN                    : boolean := false;  -- implement instruction cache
    ICACHE_NUM_BLOCKS            : natural := 4;      -- i-cache: number of blocks (min 1), has to be a power of 2
    ICACHE_BLOCK_SIZE            : natural := 64;     -- i-cache: block size in bytes (min 4), has to be a power of 2

    -- Internal Data Cache (dCACHE) --
    DCACHE_EN                    : boolean := false;  -- implement data cache
    DCACHE_NUM_BLOCKS            : natural := 4;      -- d-cache: number of blocks (min 1), has to be a power of 2
    DCACHE_BLOCK_SIZE            : natural := 64;     -- d-cache: block size in bytes (min 4), has to be a power of 2

    -- Execute in-place module (XIP) --
    XIP_EN                       : boolean := false;  -- implement execute in place module (XIP)?
    XIP_CACHE_EN                 : boolean := false;  -- implement XIP cache?
    XIP_CACHE_NUM_BLOCKS         : natural range 1 to 256 := 8;     -- number of blocks (min 1), has to be a power of 2
    XIP_CACHE_BLOCK_SIZE         : natural range 1 to 2**16 := 256; -- block size in bytes (min 4), has to be a power of 2

    -- External Interrupts Controller (XIRQ) --
    XIRQ_NUM_CH                  : natural := 0;      -- number of external IRQ channels (0..32)
    XIRQ_TRIGGER_TYPE            : std_ulogic_vector(31 downto 0) := x"ffffffff"; -- trigger type: 0=level, 1=edge
    XIRQ_TRIGGER_POLARITY        : std_ulogic_vector(31 downto 0) := x"ffffffff"; -- trigger polarity: 0=low-level/falling-edge, 1=high-level/rising-edge

    -- Processor peripherals --
    IO_GPIO_NUM                  : natural := 0;      -- number of GPIO input/output pairs (0..64)
    IO_MTIME_EN                  : boolean := false;  -- implement machine system timer (MTIME)?
    IO_UART0_EN                  : boolean := false;  -- implement primary universal asynchronous receiver/transmitter (UART0)?
    IO_UART0_RX_FIFO             : natural := 1;      -- RX fifo depth, has to be a power of two, min 1
    IO_UART0_TX_FIFO             : natural := 1;      -- TX fifo depth, has to be a power of two, min 1
    IO_UART1_EN                  : boolean := false;  -- implement secondary universal asynchronous receiver/transmitter (UART1)?
    IO_UART1_RX_FIFO             : natural := 1;      -- RX fifo depth, has to be a power of two, min 1
    IO_UART1_TX_FIFO             : natural := 1;      -- TX fifo depth, has to be a power of two, min 1
    IO_SPI_EN                    : boolean := false;  -- implement serial peripheral interface (SPI)?
    IO_SPI_FIFO                  : natural := 1;      -- SPI RTX fifo depth, has to be a power of two, min 1
    IO_TWI_EN                    : boolean := false;  -- implement two-wire interface (TWI)?
    IO_PWM_NUM_CH                : natural := 0;      -- number of PWM channels to implement (0..12); 0 = disabled
    IO_WDT_EN                    : boolean := false;  -- implement watch dog timer (WDT)?
    IO_TRNG_EN                   : boolean := false;  -- implement true random number generator (TRNG)?
    IO_TRNG_FIFO                 : natural := 1;      -- TRNG fifo depth, has to be a power of two, min 1
    IO_CFS_EN                    : boolean := false;  -- implement custom functions subsystem (CFS)?
    IO_CFS_CONFIG                : std_ulogic_vector(31 downto 0) := x"00000000"; -- custom CFS configuration generic
    IO_CFS_IN_SIZE               : positive := 32;    -- size of CFS input conduit in bits
    IO_CFS_OUT_SIZE              : positive := 32;    -- size of CFS output conduit in bits
    IO_NEOLED_EN                 : boolean := false;  -- implement NeoPixel-compatible smart LED interface (NEOLED)?
    IO_NEOLED_TX_FIFO            : natural := 1;      -- NEOLED TX FIFO depth, 1..32k, has to be a power of two
    IO_GPTMR_EN                  : boolean := false;  -- implement general purpose timer (GPTMR)?
    IO_ONEWIRE_EN                : boolean := false   -- implement 1-wire interface (ONEWIRE)?
  );
  port (
    -- Global control --
    clk_i          : in  std_ulogic; -- global clock, rising edge
    rstn_i         : in  std_ulogic; -- global reset, low-active, async

    -- JTAG on-chip debugger interface (available if ON_CHIP_DEBUGGER_EN = true) --
    jtag_trst_i    : in  std_ulogic := 'U'; -- low-active TAP reset (optional)
    jtag_tck_i     : in  std_ulogic := 'U'; -- serial clock
    jtag_tdi_i     : in  std_ulogic := 'U'; -- serial data input
    jtag_tdo_o     : out std_ulogic;        -- serial data output
    jtag_tms_i     : in  std_ulogic := 'U'; -- mode select

    -- AvalonMM interface
    read_o         : out std_logic;
    write_o        : out std_logic;
    waitrequest_i  : in  std_logic := '0';
    byteenable_o   : out std_logic_vector(3 downto 0);
    address_o      : out std_logic_vector(31 downto 0);
    writedata_o    : out std_logic_vector(31 downto 0);
    readdata_i     : in  std_logic_vector(31 downto 0) := (others => '0');

    -- XIP (execute in place via SPI) signals (available if IO_XIP_EN = true) --
    xip_csn_o      : out std_ulogic; -- chip-select, low-active
    xip_clk_o      : out std_ulogic; -- serial clock
    xip_dat_i      : in  std_ulogic := 'L'; -- device data input
    xip_dat_o      : out std_ulogic; -- controller data output

    -- GPIO (available if IO_GPIO_EN = true) --
    gpio_o         : out std_ulogic_vector(63 downto 0); -- parallel output
    gpio_i         : in  std_ulogic_vector(63 downto 0) := (others => 'U'); -- parallel input

    -- primary UART0 (available if IO_UART0_EN = true) --
    uart0_txd_o    : out std_ulogic; -- UART0 send data
    uart0_rxd_i    : in  std_ulogic := 'U'; -- UART0 receive data
    uart0_rts_o    : out std_ulogic; -- HW flow control: UART0.RX ready to receive ("RTR"), low-active, optional
    uart0_cts_i    : in  std_ulogic := 'L'; -- HW flow control: UART0.TX allowed to transmit, low-active, optional

    -- secondary UART1 (available if IO_UART1_EN = true) --
    uart1_txd_o    : out std_ulogic; -- UART1 send data
    uart1_rxd_i    : in  std_ulogic := 'U'; -- UART1 receive data
    uart1_rts_o    : out std_ulogic; -- HW flow control: UART1.RX ready to receive ("RTR"), low-active, optional
    uart1_cts_i    : in  std_ulogic := 'L'; -- HW flow control: UART1.TX allowed to transmit, low-active, optional

    -- SPI (available if IO_SPI_EN = true) --
    spi_clk_o      : out std_ulogic; -- SPI serial clock
    spi_dat_o      : out std_ulogic; -- controller data out, peripheral data in
    spi_dat_i      : in  std_ulogic := 'U'; -- controller data in, peripheral data out
    spi_csn_o      : out std_ulogic_vector(07 downto 0); -- chip-select

    -- TWI (available if IO_TWI_EN = true) --
    twi_sda_i      : in  std_ulogic := 'H'; -- serial data line sense input
    twi_sda_o      : out std_ulogic; -- serial data line output (pull low only)
    twi_scl_i      : in  std_ulogic := 'H'; -- serial clock line sense input
    twi_scl_o      : out std_ulogic; -- serial clock line output (pull low only)

    -- 1-Wire Interface (available if IO_ONEWIRE_EN = true) --
    onewire_i      : in  std_ulogic := 'H'; -- 1-wire bus sense input
    onewire_o      : out std_ulogic; -- 1-wire bus output (pull low only)

    -- PWM (available if IO_PWM_NUM_CH > 0) --
    pwm_o          : out std_ulogic_vector(11 downto 0); -- pwm channels

    -- Custom Functions Subsystem IO (available if IO_CFS_EN = true) --
    cfs_in_i       : in  std_ulogic_vector(IO_CFS_IN_SIZE-1  downto 0) := (others => 'U'); -- custom CFS inputs conduit
    cfs_out_o      : out std_ulogic_vector(IO_CFS_OUT_SIZE-1 downto 0); -- custom CFS outputs conduit

    -- NeoPixel-compatible smart LED interface (available if IO_NEOLED_EN = true) --
    neoled_o       : out std_ulogic; -- async serial data line

    -- External platform interrupts (available if XIRQ_NUM_CH > 0) --
    xirq_i         : in  std_ulogic_vector(31 downto 0) := (others => 'L'); -- IRQ channels

    -- CPU interrupts --
    mtime_irq_i    : in  std_ulogic := 'L'; -- machine timer interrupt, available if IO_MTIME_EN = false
    msw_irq_i      : in  std_ulogic := 'L'; -- machine software interrupt
    mext_irq_i     : in  std_ulogic := 'L'  -- machine external interrupt
  );
end neorv32_top_avalonmm;

architecture neorv32_top_avalonmm_rtl of neorv32_top_avalonmm is

  -- Wishbone bus interface (available if XBUS_EN = true) --
  signal wb_adr_o : std_ulogic_vector(31 downto 0); -- address
  signal wb_dat_i : std_ulogic_vector(31 downto 0) := (others => 'U'); -- read data
  signal wb_dat_o : std_ulogic_vector(31 downto 0); -- write data
  signal wb_we_o  : std_ulogic; -- read/write
  signal wb_sel_o : std_ulogic_vector(03 downto 0); -- byte enable
  signal wb_stb_o : std_ulogic; -- strobe
  signal wb_cyc_o : std_ulogic; -- valid cycle
  signal wb_ack_i : std_ulogic := 'L'; -- transfer acknowledge
  signal wb_err_i : std_ulogic := 'L'; -- transfer error

begin

  neorv32_top_map : neorv32_top
  generic map (
    -- General --
    CLOCK_FREQUENCY => CLOCK_FREQUENCY,
    HART_ID => HART_ID,
    JEDEC_ID => JEDEC_ID,

    -- On-Chip Debugger (OCD) --
    ON_CHIP_DEBUGGER_EN => ON_CHIP_DEBUGGER_EN,

    -- RISC-V CPU Extensions --
    CPU_EXTENSION_RISCV_B => CPU_EXTENSION_RISCV_B,
    CPU_EXTENSION_RISCV_C => CPU_EXTENSION_RISCV_C,
    CPU_EXTENSION_RISCV_E => CPU_EXTENSION_RISCV_E,
    CPU_EXTENSION_RISCV_M => CPU_EXTENSION_RISCV_M,
    CPU_EXTENSION_RISCV_U => CPU_EXTENSION_RISCV_U,
    CPU_EXTENSION_RISCV_Zfinx => CPU_EXTENSION_RISCV_Zfinx,
    CPU_EXTENSION_RISCV_Zicntr => CPU_EXTENSION_RISCV_Zicntr,
    CPU_EXTENSION_RISCV_Zihpm => CPU_EXTENSION_RISCV_Zihpm,
    CPU_EXTENSION_RISCV_Zmmul => CPU_EXTENSION_RISCV_Zmmul,
    CPU_EXTENSION_RISCV_Zxcfu => CPU_EXTENSION_RISCV_Zxcfu,

    -- Extension Options --
    FAST_MUL_EN => FAST_MUL_EN,
    FAST_SHIFT_EN => FAST_SHIFT_EN,

    -- Physical Memory Protection (PMP) --
    PMP_NUM_REGIONS => PMP_NUM_REGIONS,
    PMP_MIN_GRANULARITY => PMP_MIN_GRANULARITY,

    -- Hardware Performance Monitors (HPM) --
    HPM_NUM_CNTS => HPM_NUM_CNTS,
    HPM_CNT_WIDTH => HPM_CNT_WIDTH,

    -- Internal Instruction memory (IMEM) --
    IMEM_EN => IMEM_EN,
    IMEM_SIZE => IMEM_SIZE,

    -- Internal Data memory (DMEM) --
    DMEM_EN => IMEM_EN,
    DMEM_SIZE => DMEM_SIZE,

    -- Internal Cache memory (iCACHE) --
    ICACHE_EN => ICACHE_EN,
    ICACHE_NUM_BLOCKS => ICACHE_NUM_BLOCKS,
    ICACHE_BLOCK_SIZE => ICACHE_BLOCK_SIZE,

    -- Internal Data Cache (dCACHE) --
    DCACHE_EN => DCACHE_EN,
    DCACHE_NUM_BLOCKS => DCACHE_NUM_BLOCKS,
    DCACHE_BLOCK_SIZE => DCACHE_BLOCK_SIZE,

    -- External bus interface (XBUS) --
    XBUS_EN => true,
    XBUS_REGSTAGE_EN => true,

    -- Execute in-place module (XIP) --
    XIP_EN => XIP_EN,
    XIP_CACHE_EN => XIP_CACHE_EN,
    XIP_CACHE_NUM_BLOCKS => XIP_CACHE_NUM_BLOCKS,
    XIP_CACHE_BLOCK_SIZE => XIP_CACHE_BLOCK_SIZE,

    -- External Interrupts Controller (XIRQ) --
    XIRQ_NUM_CH => XIRQ_NUM_CH,
    XIRQ_TRIGGER_TYPE => XIRQ_TRIGGER_TYPE,
    XIRQ_TRIGGER_POLARITY => XIRQ_TRIGGER_POLARITY,

    -- Processor peripherals --
    IO_GPIO_NUM => IO_GPIO_NUM,
    IO_MTIME_EN => IO_MTIME_EN,
    IO_UART0_EN => IO_UART0_EN,
    IO_UART0_RX_FIFO => IO_UART0_RX_FIFO,
    IO_UART0_TX_FIFO => IO_UART0_TX_FIFO,
    IO_UART1_EN => IO_UART1_EN,
    IO_UART1_RX_FIFO => IO_UART1_RX_FIFO,
    IO_UART1_TX_FIFO => IO_UART1_TX_FIFO,
    IO_SPI_EN => IO_SPI_EN,
    IO_SPI_FIFO => IO_SPI_FIFO,
    IO_TWI_EN => IO_TWI_EN,
    IO_PWM_NUM_CH => IO_PWM_NUM_CH,
    IO_WDT_EN => IO_WDT_EN,
    IO_TRNG_EN => IO_TRNG_EN,
    IO_TRNG_FIFO => IO_TRNG_FIFO,
    IO_CFS_EN => IO_CFS_EN,
    IO_CFS_CONFIG => IO_CFS_CONFIG,
    IO_CFS_IN_SIZE => IO_CFS_IN_SIZE,
    IO_CFS_OUT_SIZE => IO_CFS_OUT_SIZE,
    IO_NEOLED_EN => IO_NEOLED_EN,
    IO_NEOLED_TX_FIFO => IO_NEOLED_TX_FIFO,
    IO_GPTMR_EN => IO_GPTMR_EN,
    IO_ONEWIRE_EN => IO_ONEWIRE_EN
    )
  port map (
    -- Global control --
    clk_i => clk_i,
    rstn_i => rstn_i,

    -- JTAG on-chip debugger interface (available if ON_CHIP_DEBUGGER_EN = true) --
    jtag_trst_i => jtag_trst_i,
    jtag_tck_i => jtag_tck_i,
    jtag_tdi_i => jtag_tdi_i,
    jtag_tdo_o => jtag_tdo_o,
    jtag_tms_i => jtag_tms_i,

    -- External bus interface (available if XBUS_EN = true) --
    xbus_adr_o => wb_adr_o,
    xbus_dat_i => wb_dat_i,
    xbus_dat_o => wb_dat_o,
    xbus_we_o  => wb_we_o,
    xbus_sel_o => wb_sel_o,
    xbus_stb_o => wb_stb_o,
    xbus_cyc_o => wb_cyc_o,
    xbus_ack_i => wb_ack_i,
    xbus_err_i => wb_err_i,

    -- XIP (execute in place via SPI) signals (available if IO_XIP_EN = true) --
    xip_csn_o => xip_csn_o,
    xip_clk_o => xip_clk_o,
    xip_dat_i => xip_dat_i,
    xip_dat_o => xip_dat_o,

    -- GPIO (available if IO_GPIO_EN = true) --
    gpio_o => gpio_o,
    gpio_i => gpio_i,

    -- primary UART0 (available if IO_UART0_EN = true) --
    uart0_txd_o => uart0_txd_o,
    uart0_rxd_i => uart0_rxd_i,
    uart0_rts_o => uart0_rts_o,
    uart0_cts_i => uart0_cts_i,

    -- secondary UART1 (available if IO_UART1_EN = true) --
    uart1_txd_o => uart1_txd_o,
    uart1_rxd_i => uart1_rxd_i,
    uart1_rts_o => uart1_rts_o,
    uart1_cts_i => uart1_cts_i,

    -- SPI (available if IO_SPI_EN = true) --
    spi_clk_o => spi_clk_o,
    spi_dat_o => spi_dat_o,
    spi_dat_i => spi_dat_i,
    spi_csn_o => spi_csn_o,

    -- TWI (available if IO_TWI_EN = true) --
    twi_sda_i => twi_sda_i,
    twi_sda_o => twi_sda_o,
    twi_scl_i => twi_scl_i,
    twi_scl_o => twi_scl_o,

    -- 1-Wire Interface (available if IO_ONEWIRE_EN = true) --
    onewire_i => onewire_i,
    onewire_o => onewire_o,

    -- PWM (available if IO_PWM_NUM_CH > 0) --
    pwm_o => pwm_o,

    -- Custom Functions Subsystem IO (available if IO_CFS_EN = true) --
    cfs_in_i => cfs_in_i,
    cfs_out_o => cfs_out_o,

    -- NeoPixel-compatible smart LED interface (available if IO_NEOLED_EN = true) --
    neoled_o => neoled_o,

    -- External platform interrupts (available if XIRQ_NUM_CH > 0) --
    xirq_i => xirq_i,

    -- CPU interrupts --
    mtime_irq_i => mtime_irq_i,
    msw_irq_i => msw_irq_i,
    mext_irq_i => mext_irq_i
  );

  -- Wishbone to AvalonMM bridge
  read_o <= '1' when (wb_stb_o = '1' and wb_we_o = '0') else '0';
  write_o <= '1' when (wb_stb_o = '1' and wb_we_o = '1') else '0';
  address_o <= std_logic_vector(wb_adr_o);
  writedata_o <= std_logic_vector(wb_dat_o);
  byteenable_o <= std_logic_vector(wb_sel_o);

  wb_dat_i <= std_ulogic_vector(readdata_i);
  wb_ack_i <= not(waitrequest_i);
  wb_err_i <= '0';

end neorv32_top_avalonmm_rtl;
