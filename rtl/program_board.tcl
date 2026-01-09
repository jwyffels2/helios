open_hw_manager
connect_hw_server
open_hw_target
# Usage:

set hw_device [lindex [get_hw_devices] 0]
current_hw_device $hw_device
refresh_hw_device $hw_device

# Find a helios.bit anywhere under ./work
set script_dir [file dirname [file normalize [info script]]]
set candidates [glob -nocomplain -types f [file join $script_dir work *\.runs impl_1 helios.bit]]

if {[llength $candidates] == 0} {
    puts "ERROR: Couldn't find helios.bit under: [file join $script_dir work]"
    puts "Hint: expected something like work/basys3-helios-vga.runs/impl_1/helios.bit"
    exit 1
}

# If multiple, pick the newest by mtime
set bitfile [lindex [lsort -command {apply {{a b} {
    expr {[file mtime $a] < [file mtime $b] ? 1 : -1}
}}} $candidates] 0]

puts "Programming with: $bitfile"
set_property PROGRAM.FILE $bitfile $hw_device
program_hw_devices $hw_device
refresh_hw_device $hw_device
puts "DONE: Programmed."
