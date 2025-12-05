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


#CAMERA HSYNC and VSYNC
#HSYNC
set_property PACKAGE_PIN M18 [get_ports {gpio_i[0]}]
#VSYNC
set_property PACKAGE_PIN L17 [get_ports {gpio_i[1]}]

#CAMERA DATA PINS
#D2
set_property PACKAGE_PIN A15 [get_ports {gpio_i[2]}]
 #D3
set_property PACKAGE_PIN B16 [get_ports {gpio_i[3]}]
#D4
set_property PACKAGE_PIN A17 [get_ports {gpio_i[4]}]
#D5
set_property PACKAGE_PIN B15 [get_ports {gpio_i[5]}]
#D6
set_property PACKAGE_PIN C15 [get_ports {gpio_i[6]}]
#D7
set_property PACKAGE_PIN A14 [get_ports {gpio_i[7]}]
#D8
set_property PACKAGE_PIN C16 [get_ports {gpio_i[8]}]
#D9
set_property PACKAGE_PIN A16 [get_ports {gpio_i[9]}]

#CAMERA PIXEL CLOCK
set_property PACKAGE_PIN P18 [get_ports {gpio_i[10]}]

#CAMERA RESET PIN
set_property PACKAGE_PIN R18 [get_ports {gpio_i[11]}]

set_property IOSTANDARD LVCMOS33 [get_ports {gpio_o[*]}]
set_property IOSTANDARD LVCMOS33 [get_ports {gpio_i[*]}]

# Camera External Clock PWM
set_property PACKAGE_PIN K17 [get_ports pwm_o[0]]

set_property IOSTANDARD LVCMOS33 [get_ports {pwm_o[*]}]


## ======================== TWI ========================

# SDA
set_property PACKAGE_PIN N17 [get_ports {twi_sda}]
set_property IOSTANDARD LVCMOS33 [get_ports {twi_sda}]
set_property PULLUP true [get_ports {twi_sda}]

# SCL
set_property PACKAGE_PIN M19 [get_ports {twi_scl}]
set_property IOSTANDARD LVCMOS33 [get_ports {twi_scl}]
set_property PULLUP true [get_ports {twi_scl}]

## ======================== END TWI ====================




## Bitstream configuration
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]
set_property CONFIG_MODE SPIx4 [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 33 [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property CFGBVS VCCO [current_design]
set_property SEVERITY {Warning} [get_drc_checks UCIO-1]
