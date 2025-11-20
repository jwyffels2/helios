@echo off
setlocal
pushd "%~dp0"

rem Default: skip running create_project.tcl
set DO_CREATE=0

rem If first arg is "create", enable it
if /I "%~1"=="--create" (
    set DO_CREATE=1
)

pushd ".\rtl\"

if "%DO_CREATE%"=="1" (
    echo Running build.tcl ...
    call vivado -mode batch -source ".\build.tcl"
) else (
    echo "Skipping build.tcl (default)."
)

echo "Running program.tcl ..."
call vivado -mode batch -source ".\program.tcl"

popd
popd
endlocal
