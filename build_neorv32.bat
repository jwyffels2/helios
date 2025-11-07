@echo off
setlocal
pushd "%~dp0"

pushd ".\third_party\helios-neorv32-setups\vivado\basys3-a7-test-setup"

call vivado -mode batch -source "create_project.tcl"
call vivado -mode batch -source "program_bitstream.tcl"

popd
popd
endlocal
