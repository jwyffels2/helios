## VGA Connector (Basys3)
## NOTE: VGA uses J18 for vga_b_o[3]. Do NOT also use J18 for UART TX.
# 100 MHz board clock
create_clock -period 10.000 [get_ports clk_i]
# Red[3:0]
set_property PACKAGE_PIN G19 [get_ports {vga_r_o[0]}]
set_property PACKAGE_PIN H19 [get_ports {vga_r_o[1]}]
set_property PACKAGE_PIN J19 [get_ports {vga_r_o[2]}]
set_property PACKAGE_PIN N19 [get_ports {vga_r_o[3]}]

# Green[3:0]
set_property PACKAGE_PIN J17 [get_ports {vga_g_o[0]}]
set_property PACKAGE_PIN H17 [get_ports {vga_g_o[1]}]
set_property PACKAGE_PIN G17 [get_ports {vga_g_o[2]}]
set_property PACKAGE_PIN D17 [get_ports {vga_g_o[3]}]

# Blue[3:0]
set_property PACKAGE_PIN N18 [get_ports {vga_b_o[0]}]
set_property PACKAGE_PIN L18 [get_ports {vga_b_o[1]}]
set_property PACKAGE_PIN K18 [get_ports {vga_b_o[2]}]
set_property PACKAGE_PIN J18 [get_ports {vga_b_o[3]}]

# Sync
set_property PACKAGE_PIN P19 [get_ports vga_hsync_o]
set_property PACKAGE_PIN R19 [get_ports vga_vsync_o]

# I/O standards for all VGA pins
set_property IOSTANDARD LVCMOS33 [get_ports {vga_r_o[*]}]
set_property IOSTANDARD LVCMOS33 [get_ports {vga_g_o[*]}]
set_property IOSTANDARD LVCMOS33 [get_ports {vga_b_o[*]}]
set_property IOSTANDARD LVCMOS33 [get_ports vga_hsync_o]
set_property IOSTANDARD LVCMOS33 [get_ports vga_vsync_o]
