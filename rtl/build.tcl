# Create Vivado project and generate bitstream
# Usage:
#   vivado -mode batch -source build.tcl -nolog -nojournal

# --------------------------------------------------------------------
# Setup
# --------------------------------------------------------------------
set board "basys3"

# Directory where THIS script lives
set script_dir [file dirname [file normalize [info script]]]

# Optional board repo (safe to keep)
set repo_abs [file normalize [file join \
    $script_dir .. third_party helios-neorv32-setups vivado vivado-board-dependencies new board_files]]
set_param board.repoPaths [list $repo_abs]

# --------------------------------------------------------------------
# Create / clean output directory
# --------------------------------------------------------------------
set outputdir [file join $script_dir work]
file mkdir $outputdir

set files [glob -nocomplain "$outputdir/*"]
if {[llength $files] != 0} {
    puts "deleting contents of $outputdir"
    file delete -force {*}$files
} else {
    puts "$outputdir is empty"
}

# --------------------------------------------------------------------
# Project / device setup
# --------------------------------------------------------------------
switch $board {
  "basys3" {
    set a7part "xc7a35tcpg236-1"
    set a7prj  "${board}-helios-vga"
  }
  default {
    error "Unknown board '$board'"
  }
}

create_project -part $a7part $a7prj $outputdir
set_property board_part digilentinc.com:${board}:part0:1.2 [current_project]
set_property target_language VHDL [current_project]

# IMPORTANT: Disable automatic hierarchy replacement
set_property source_mgmt_mode None [current_project]

# --------------------------------------------------------------------
# Top-level RTL
# --------------------------------------------------------------------
set top_vhdl [file join $script_dir helios.vhdl]
if {![file exists $top_vhdl]} {
    error "Missing top-level file: $top_vhdl"
}
add_files $top_vhdl
puts "=== RTL files in project ==="
foreach f [get_files] { puts $f }
puts "============================"
# --------------------------------------------------------------------
# Local RTL dependencies (VGA)
# --------------------------------------------------------------------
set local_rtl {}

# VGA timing generator used by helios.vhdl
set vga_timing [file join $script_dir vga_640x480_timing.vhd]
if {![file exists $vga_timing]} {
    error "Missing VGA timing file: $vga_timing"
}
lappend local_rtl $vga_timing

set fb_file [file join $script_dir fb_bram_rgb332_160x120.vhd]
if {![file exists $fb_file]} { error "Missing FB file: $fb_file" }
lappend local_rtl $fb_file

#set vga_dir [file join $script_dir vga_fb]
#if {[file isdirectory $vga_dir]} {
#    set vga_files [glob -nocomplain [file join $vga_dir *.vhd]]
#    foreach f $vga_files { lappend local_rtl $f }
#}

if {[llength $local_rtl] > 0} {
    add_files $local_rtl
}
puts "=== RTL files in project (after deps) ==="
foreach f [get_files] { puts $f }
puts "========================================"
# Set design top
set_property top helios [current_fileset]

# --------------------------------------------------------------------
# Constraints
# --------------------------------------------------------------------
set xdc_files [glob -nocomplain [file join $script_dir *.xdc]]
if {[llength $xdc_files] == 0} {
    puts "WARNING: No XDC constraint files found"
} else {
    add_files -fileset constrs_1 $xdc_files
}

# --------------------------------------------------------------------
# Build
# --------------------------------------------------------------------
launch_runs synth_1 -jobs 4
wait_on_run synth_1

launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

# Cleanup
set_param board.repoPaths ""
puts "DONE: VGA-only bitstream generated."
