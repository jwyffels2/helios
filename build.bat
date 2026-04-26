@echo off
setlocal
pushd "%~dp0"

rem This wrapper is the Windows entry point for the containerized NEORV32 build.
rem It deliberately builds inside Podman so reviewers do not need a local RISC-V
rem GNAT toolchain installed on Windows. The batch file should fail immediately
rem when any underlying build step fails, because otherwise CI/manual testing can
rem look successful while the actual container command printed an error.

rem ----------------------------------------------------
rem Parse flags from command line.
rem --create  rebuilds the NEORV32 setup image before the normal app/test build.
rem --program calls the existing board-programming flow before the normal build.
rem --test    builds the tests crate instead of the application crate.
rem ----------------------------------------------------
set "DO_CREATE=0"
set "DO_TEST=0"
set "DO_PROGRAM=0"

for %%A in (%*) do (
    if /I "%%~A"=="--create" set "DO_CREATE=1"
    if /I "%%~A"=="--test"   set "DO_TEST=1"
    if /I "%%~A"=="--program"   set "DO_PROGRAM=1"
)


rem ----------------------------------------------------
rem Optional setup/programming steps.
rem Each command is followed by an errorlevel check so the script returns the
rem real failure to GitHub Actions or to the developer running it locally.
rem ----------------------------------------------------
if %DO_CREATE%==1 (
    podman build --no-cache -t helios-build -f ./build.dockerfile .
    if errorlevel 1 exit /b %errorlevel%
    call .\build_neorv32.bat --create
    if errorlevel 1 exit /b %errorlevel%
)
if %DO_PROGRAM%==1 (
    call .\build_neorv32.bat
    if errorlevel 1 exit /b %errorlevel%
)

rem Always do a normal container build as well. This refreshes the helios-build
rem image used for the final project/test compilation step.
podman build -t helios-build -f ./build.dockerfile .
if errorlevel 1 exit /b %errorlevel%

rem ----------------------------------------------------
rem Choose the expected ELF path depending on --test.
rem build_neorv32_project.sh will run alr build inside the right project and
rem then convert that ELF into the NEORV32 .exe image.
rem ----------------------------------------------------
if %DO_TEST%==1 (
    set "ELF_PATH=./tests/bin/tests"
) else (
    set "ELF_PATH=./bin/helios"
)

podman run --rm -v "%CD%:/workspace" -w /workspace helios-build ^
    ./build_neorv32_project.sh "%ELF_PATH%"
if errorlevel 1 exit /b %errorlevel%

popd
endlocal
