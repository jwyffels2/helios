@echo off
setlocal
pushd "%~dp0"

rem ----------------------------------------------------
rem Parse flags from command line
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
rem Optional: create image + run build_neorv32.bat with --create
rem ----------------------------------------------------
if %DO_CREATE%==1 (
    podman build --no-cache -t helios-build -f ./build.dockerfile . || goto :fail
    call .\build_neorv32.bat --create || goto :fail
)
if %DO_PROGRAM%==1 (
    call .\build_neorv32.bat || goto :fail
)

rem Always do a normal build as well
podman build -t helios-build -f ./build.dockerfile . || goto :fail

rem ----------------------------------------------------
rem Choose ELF path depending on --test
rem ----------------------------------------------------
if %DO_TEST%==1 (
    set "ELF_PATH=./tests/bin/tests"
) else (
    set "ELF_PATH=./bin/helios"
)

podman run --rm -v "%CD%:/workspace" -w /workspace helios-build ^
    ./build_neorv32_project.sh "%ELF_PATH%" || goto :fail

popd
endlocal
exit /b 0

:fail
set "ERR=%ERRORLEVEL%"
popd
endlocal & exit /b %ERR%
