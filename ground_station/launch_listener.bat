@echo off
setlocal EnableExtensions EnableDelayedExpansion
pushd "%~dp0"

set "UART0_HOST="
set "IMAGE_NAME=python:3.12-slim"
set "EXPECT_UART0=0"
set "PARSE_ERROR="
set "PARSE_ERROR_MSG="

for %%A in (%*) do (
    if not defined PARSE_ERROR (
        set "ARG=%%~A"

        if "!EXPECT_UART0!"=="1" (
            if "!ARG:~0,2!"=="--" (
                set "PARSE_ERROR=1"
                set "PARSE_ERROR_MSG=Error: --uart0 requires a value."
            ) else (
                set "UART0_HOST=!ARG!"
                set "EXPECT_UART0=0"
            )
        ) else (
            if /I "!ARG!"=="--uart0" (
                set "EXPECT_UART0=1"
            ) else (
                set "PARSE_ERROR=1"
                set "PARSE_ERROR_MSG=Error: unknown argument !ARG!."
            )
        )
    )
)

if defined PARSE_ERROR (
    echo !PARSE_ERROR_MSG!
    echo.
    goto usage
)

if "!EXPECT_UART0!"=="1" (
    echo Error: --uart0 requires a value.
    echo.
    goto usage
)

if not defined UART0_HOST (
    echo Error: missing required argument --uart0.
    echo.
    goto usage
)

echo Preparing UART0 for container passthrough...
echo.
echo Host device: %UART0_HOST%
echo Container alias: /dev/UART0
echo.

set "ROOTLESS="
for /f "usebackq delims=" %%R in (`podman info --format "{{.Host.Security.Rootless}}" 2^>nul`) do set "ROOTLESS=%%R"

if not defined ROOTLESS (
    echo Error: failed to query Podman rootless status.
    echo Ensure Podman is installed and available in PATH.
    popd
    endlocal & exit /b 1
)

if /I not "%ROOTLESS%"=="false" (
    echo Error: Podman must be rootful.
    popd
    endlocal & exit /b 1
)

podman run -it --rm ^
    -v "%CD%:/workspace" ^
    -w /workspace ^
    --entrypoint bash ^
    --device=%UART0_HOST%:/dev/UART0:rwm ^
    %IMAGE_NAME%
set "EXIT_CODE=%ERRORLEVEL%"

popd
endlocal & exit /b %EXIT_CODE%

:usage
echo Usage: %~nx0 --uart0 ^<linux-tty-path^>
echo Example: %~nx0 --uart0 /dev/ttyUSB0
popd
endlocal & exit /b 1
