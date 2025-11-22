# Simple bitstream programming script for Basys3
# Usage: vivado -mode batch -source program_bitstream.tcl
# Directory where THIS script lives
set script_dir [file dirname [file normalize [info script]]]

open_hw_manager
connect_hw_server
open_hw_target

# Select device
current_hw_device [lindex [get_hw_devices] 0]
refresh_hw_device [current_hw_device]
# Program bitstream
set bitfile "$script_dir/work/basys3-neorv32.runs/impl_1/helios.bit"
set_property PROGRAM.FILE $bitfile [current_hw_device]
program_hw_devices [current_hw_device]

# Close connection
refresh_hw_device [current_hw_device]
close_hw_target
disconnect_hw_server
