# Create Vivado project and generate bitstream
# Usage (from C:\helios\rtl):
#   vivado -mode batch -source create_project.tcl

# --------------------------------------------------------------------
# Setup
# --------------------------------------------------------------------
set board "basys3"

# Directory where THIS script lives
set script_dir [file dirname [file normalize [info script]]]

# Board files repo (relative to C:\helios\rtl):
#   ..\third_party\helios-neorv32-setups\vivado\vivado-board-dependencies\new\board_files
set repo_abs [file normalize [file join $script_dir .. third_party helios-neorv32-setups vivado vivado-board-dependencies new board_files]]
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
    set a7prj  "${board}-neorv32"
  }
  default {
    error "Unknown board '$board'"
  }
}

# Create project in work/
create_project -part $a7part $a7prj $outputdir

set_property board_part digilentinc.com:${board}:part0:1.2 [current_project]
set_property target_language VHDL [current_project]

# --------------------------------------------------------------------
# NEORV32 RTL sources
#   Assumes NEORV32 at: ..\third_party\helios-neorv32-setups\neorv32
# --------------------------------------------------------------------
set neorv32_root     [file normalize [file join $script_dir .. third_party helios-neorv32-setups neorv32]]
set neorv32_rtl_dir  [file join $neorv32_root rtl]
set neorv32_sim_dir  [file join $neorv32_root sim]

# Add core RTL
if {[file isdirectory [file join $neorv32_rtl_dir core]]} {
    set neorv32_core_files [glob -nocomplain [file join $neorv32_rtl_dir core *.vhd]]
    if {[llength $neorv32_core_files] == 0} {
        puts "WARNING: No NEORV32 core files found in $neorv32_rtl_dir/core"
    } else {
        add_files $neorv32_core_files
        set_property library neorv32 [get_files $neorv32_core_files]
    }
} else {
    puts "WARNING: NEORV32 core directory not found: [file join $neorv32_rtl_dir core]"
}

# Optionally add system_integration (if directory exists in your repo)
if {[file isdirectory [file join $neorv32_rtl_dir system_integration]]} {
    set neorv32_sys_files [glob -nocomplain [file join $neorv32_rtl_dir system_integration *.vhd]]
    if {[llength $neorv32_sys_files] > 0} {
        add_files $neorv32_sys_files
        set_property library neorv32 [get_files $neorv32_sys_files]
    }
}

# --------------------------------------------------------------------
# Framebuffer RTL sources (XBUS -> VRAM)
# --------------------------------------------------------------------
set fb_vram_files [list \
  [file join $script_dir vram_xbus_slave.vhd] \
  [file join $script_dir vram_rgb332_dp.vhd] \
]
foreach f $fb_vram_files {
  if {![file exists $f]} {
    error "Framebuffer RTL file not found: $f"
  }
}
add_files $fb_vram_files

# --------------------------------------------------------------------
# Your wrapper top-level (instantiates neorv32_top)
#   File: C:\helios\rtl\helios.vhd
# --------------------------------------------------------------------
set wrapper_vhdl [file join $script_dir helios.vhdl]
if {![file exists $wrapper_vhdl]} {
    error "Wrapper VHDL file not found: $wrapper_vhdl"
}
add_files $wrapper_vhdl

# Set wrapper as design top
set_property top helios [current_fileset]

# --------------------------------------------------------------------
# Constraints
#   Expect *.xdc files in C:\helios\rtl (same dir as this script)
# --------------------------------------------------------------------
set fileset_constraints [glob -nocomplain [file join $script_dir *.xdc]]
if {[llength $fileset_constraints] == 0} {
    puts "WARNING: No XDC constraint files found in $script_dir"
} else {
    add_files -fileset constrs_1 $fileset_constraints
}

# --------------------------------------------------------------------
# Simulation-only sources (optional)
#   Using original NEORV32 sim files, if present
#   C:\helios\third_party\neorv32\sim\neorv32_tb.vhd, sim_uart_rx.vhd
# --------------------------------------------------------------------
set sim_tb  [file join $neorv32_sim_dir neorv32_tb.vhd]
set sim_uart [file join $neorv32_sim_dir sim_uart_rx.vhd]

set fileset_sim {}
if {[file exists $sim_tb]} {
    lappend fileset_sim $sim_tb
}
if {[file exists $sim_uart]} {
    lappend fileset_sim $sim_uart
}

if {[llength $fileset_sim] > 0} {
    add_files -fileset sim_1 $fileset_sim
} else {
    puts "NOTE: No NEORV32 simulation files were added (not found)."
}

# --------------------------------------------------------------------
# Run synthesis, implementation, and bitstream
# --------------------------------------------------------------------
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

# Optionally clear board repo paths again
set_param board.repoPaths ""
puts "Done."
