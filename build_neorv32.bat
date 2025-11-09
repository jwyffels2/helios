@echo off
setlocal
pushd "%~dp0"

rem Default: skip running create_project.tcl
set DO_CREATE=0

rem If first arg is "create", enable it
if /I "%~1"=="--create" (
    set DO_CREATE=1
)

pushd ".\third_party\helios-neorv32-setups\vivado\basys3-a7-test-setup"

if "%DO_CREATE%"=="1" (
    echo Running create_project.tcl ...
    call vivado -mode batch -source "create_project.tcl"
) else (
    echo "Skipping create_project.tcl (default)."
)

echo "Running program_bitstream.tcl ..."
call vivado -mode batch -source "program_bitstream.tcl"

popd
popd
endlocal
