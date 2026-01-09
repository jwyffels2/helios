# ============================================================================
# program_board.tcl
#
# Purpose:
#   Programs the Basys3 FPGA with the most recently generated helios.bit file.
#
# Usage:
#   vivado -mode batch -source program_board.tcl
#
# Behavior:
#   • Connects to the local Vivado hardware server
#   • Detects the attached FPGA via JTAG
#   • Automatically locates the newest helios.bit under ./work
#   • Programs the device
# ============================================================================

# --------------------------------------------------------------------
# Open Vivado hardware manager and connect to local hardware server
# --------------------------------------------------------------------
open_hw_manager
connect_hw_server

# Open the JTAG target (Basys3 board)
open_hw_target

# --------------------------------------------------------------------
# Select the first detected FPGA device
# (Basys3 has a single Artix-7 device)
# --------------------------------------------------------------------
set hw_device [lindex [get_hw_devices] 0]
current_hw_device $hw_device

# Ensure the device state is up to date
refresh_hw_device $hw_device

# --------------------------------------------------------------------
# Locate the generated helios.bit file
# Search recursively under ./work for implementation outputs
# --------------------------------------------------------------------
set script_dir [file dirname [file normalize [info script]]]

# Look for helios.bit under any *.runs/impl_1 directory
set candidates [glob -nocomplain -types f \
  [file join $script_dir work *\.runs impl_1 helios.bit]]

# Abort if no bitstream is found
if {[llength $candidates] == 0} {
    puts "ERROR: Couldn't find helios.bit under: [file join $script_dir work]"
    puts "Hint: expected something like work/basys3-helios-vga.runs/impl_1/helios.bit"
    exit 1
}

# --------------------------------------------------------------------
# If multiple bitstreams exist, select the newest one by timestamp
# --------------------------------------------------------------------
set bitfile [lindex [lsort -command {apply {{a b} {
    expr {[file mtime $a] < [file mtime $b] ? 1 : -1}
}}} $candidates] 0]

puts "Programming with: $bitfile"

# --------------------------------------------------------------------
# Program the FPGA
# --------------------------------------------------------------------
set_property PROGRAM.FILE $bitfile $hw_device
program_hw_devices $hw_device

# Refresh device status after programming
refresh_hw_device $hw_device

puts "DONE: Programmed."
