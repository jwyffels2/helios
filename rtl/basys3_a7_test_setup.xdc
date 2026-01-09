## ============================================================
## System Clock
## ============================================================
## Basys3 provides a 100 MHz onboard oscillator on pin W5.
## This clock drives the entire VGA pipeline and framebuffer logic.
set_property -dict { PACKAGE_PIN W5 IOSTANDARD LVCMOS33 } [get_ports clk_i]

## Declare the clock period explicitly for timing analysis.
## 100 MHz → 10 ns period.
create_clock -period 10.000 [get_ports clk_i]


## ============================================================
## VGA Synchronization Signals
## ============================================================
## Horizontal sync (active-low VGA HSYNC)
set_property -dict { PACKAGE_PIN P19 IOSTANDARD LVCMOS33 } [get_ports vga_hsync_o]

## Vertical sync (active-low VGA VSYNC)
set_property -dict { PACKAGE_PIN R19 IOSTANDARD LVCMOS33 } [get_ports vga_vsync_o]


## ============================================================
## Reset Input
## ============================================================
## Center button on Basys3 used as ACTIVE-HIGH reset.
## Pulldown ensures reset is deasserted when button is not pressed.
set_property PACKAGE_PIN U18 [get_ports rst_i]
set_property IOSTANDARD LVCMOS33 [get_ports rst_i]
set_property PULLDOWN true [get_ports rst_i]


## ============================================================
## VGA RGB Output (4 bits per channel)
## ============================================================
## Each color channel uses 4 FPGA pins to drive the VGA DAC ladder.
## Color depth: RGB444 (12-bit total).

## --- Red Channel ---
set_property -dict { PACKAGE_PIN G19 IOSTANDARD LVCMOS33 } [get_ports {vga_r_o[0]}]
set_property -dict { PACKAGE_PIN H19 IOSTANDARD LVCMOS33 } [get_ports {vga_r_o[1]}]
set_property -dict { PACKAGE_PIN J19 IOSTANDARD LVCMOS33 } [get_ports {vga_r_o[2]}]
set_property -dict { PACKAGE_PIN N19 IOSTANDARD LVCMOS33 } [get_ports {vga_r_o[3]}]

## --- Green Channel ---
set_property -dict { PACKAGE_PIN J17 IOSTANDARD LVCMOS33 } [get_ports {vga_g_o[0]}]
set_property -dict { PACKAGE_PIN H17 IOSTANDARD LVCMOS33 } [get_ports {vga_g_o[1]}]
set_property -dict { PACKAGE_PIN G17 IOSTANDARD LVCMOS33 } [get_ports {vga_g_o[2]}]
set_property -dict { PACKAGE_PIN D17 IOSTANDARD LVCMOS33 } [get_ports {vga_g_o[3]}]

## --- Blue Channel ---
set_property -dict { PACKAGE_PIN N18 IOSTANDARD LVCMOS33 } [get_ports {vga_b_o[0]}]
set_property -dict { PACKAGE_PIN L18 IOSTANDARD LVCMOS33 } [get_ports {vga_b_o[1]}]
set_property -dict { PACKAGE_PIN K18 IOSTANDARD LVCMOS33 } [get_ports {vga_b_o[2]}]
set_property -dict { PACKAGE_PIN J18 IOSTANDARD LVCMOS33 } [get_ports {vga_b_o[3]}]
