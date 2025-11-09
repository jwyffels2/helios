
@echo off
pushd "%~dp0"

rem Default: skip running create_project.tcl

rem If first arg is "create", enable it
if /I "%~1"=="--create" (
    call .\build_neorv32.bat --create
) else (
    call .\build_neorv32.bat
)



podman build -t helios-build -f ./build.dockerfile .

podman run --rm -v "%CD% :/workspace" -w /workspace helios-build ./build_hal_fw.sh

popd
