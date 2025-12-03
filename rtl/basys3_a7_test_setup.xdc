## ===============================================================
## Basys3 Minimal Constraints for NEORV32 Bootloader Test Setup
## ===============================================================

## Clock input (100 MHz)
set_property PACKAGE_PIN W5 [get_ports clk_i]
set_property IOSTANDARD LVCMOS33 [get_ports clk_i]
create_clock -period 10.000 -name sys_clk_pin [get_ports clk_i]

## Reset button (BTNC)
set_property PACKAGE_PIN U18 [get_ports rstn_i]
set_property IOSTANDARD LVCMOS33 [get_ports rstn_i]

## UART0 (USB-UART bridge on Basys3)
# J17 = RX from FTDI to FPGA (uart0_rxd_i)
# J18 = TX from FPGA to FTDI (uart0_txd_o)
set_property PACKAGE_PIN B18 [get_ports uart0_rxd_i]
set_property IOSTANDARD LVCMOS33 [get_ports uart0_rxd_i]
set_property PACKAGE_PIN A18 [get_ports uart0_txd_o]
set_property IOSTANDARD LVCMOS33 [get_ports uart0_txd_o]

## Optional GPIO outputs (connect to on-board LEDs LD0–LD7)
set_property PACKAGE_PIN U16 [get_ports {gpio_o[0]}]
set_property PACKAGE_PIN E19 [get_ports {gpio_o[1]}]
set_property PACKAGE_PIN U19 [get_ports {gpio_o[2]}]
set_property PACKAGE_PIN V19 [get_ports {gpio_o[3]}]
set_property PACKAGE_PIN W18 [get_ports {gpio_o[4]}]
set_property PACKAGE_PIN U15 [get_ports {gpio_o[5]}]
set_property PACKAGE_PIN U14 [get_ports {gpio_o[6]}]
#set_property PACKAGE_PIN V14 [get_ports {gpio_o[7]}]

# RESET PIN
#set_property PACKAGE_PIN V14 [get_ports {gpio_o[7]}]


set_property IOSTANDARD LVCMOS33 [get_ports {gpio_o[*]}]


# Camera External Clock PWM
set_property PACKAGE_PIN V14 [get_ports pwm_o[0]]
set_property IOSTANDARD LVCMOS33 [get_ports {pwm_o[*]}]

#========================TWI==========================
# TWI_SDA_I and TWI_SDA_O should be the same pin
set_property PACKAGE_PIN P17 [get_ports twi_sda_i]
set_property IOSTANDARD LVCMOS33 [get_ports twi_sda_i]

set_property PACKAGE_PIN P17 [get_ports twi_sda_o]
set_property IOSTANDARD LVCMOS33 [get_ports twi_sda_o]

# TWI_SCL_I and TWI_SCL_O should be the same pin
set_property PACKAGE_PIN N17 [get_ports twi_scl_i]
set_property IOSTANDARD LVCMOS33 [get_ports twi_scl_i]

set_property PACKAGE_PIN N17 [get_ports twi_scl_o]
set_property IOSTANDARD LVCMOS33 [get_ports twi_scl_o]
#=====================END OF TWI======================

#========================VGA==========================

set_property -dict { PACKAGE_PIN G19 IOSTANDARD LVCMOS33 } [get_ports {vga_r[0]}]
set_property -dict { PACKAGE_PIN H19 IOSTANDARD LVCMOS33 } [get_ports {vga_r[1]}]
set_property -dict { PACKAGE_PIN J19 IOSTANDARD LVCMOS33 } [get_ports {vga_r[2]}]
set_property -dict { PACKAGE_PIN N19 IOSTANDARD LVCMOS33 } [get_ports {vga_r[3]}]

set_property -dict { PACKAGE_PIN J17 IOSTANDARD LVCMOS33 } [get_ports {vga_g[0]}]
set_property -dict { PACKAGE_PIN H17 IOSTANDARD LVCMOS33 } [get_ports {vga_g[1]}]
set_property -dict { PACKAGE_PIN G17 IOSTANDARD LVCMOS33 } [get_ports {vga_g[2]}]
set_property -dict { PACKAGE_PIN D17 IOSTANDARD LVCMOS33 } [get_ports {vga_g[3]}]

set_property -dict { PACKAGE_PIN N18 IOSTANDARD LVCMOS33 } [get_ports {vga_b[0]}]
set_property -dict { PACKAGE_PIN L18 IOSTANDARD LVCMOS33 } [get_ports {vga_b[1]}]
set_property -dict { PACKAGE_PIN K18 IOSTANDARD LVCMOS33 } [get_ports {vga_b[2]}]
set_property -dict { PACKAGE_PIN J18 IOSTANDARD LVCMOS33 } [get_ports {vga_b[3]}]

set_property -dict { PACKAGE_PIN P19 IOSTANDARD LVCMOS33 } [get_ports {vga_hs}]
set_property -dict { PACKAGE_PIN R19 IOSTANDARD LVCMOS33 } [get_ports {vga_vs}]

#=====================END OF VGA======================


## Bitstream configuration
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]
set_property CONFIG_MODE SPIx4 [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 33 [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property CFGBVS VCCO [current_design]
set_property SEVERITY {Warning} [get_drc_checks UCIO-1]
