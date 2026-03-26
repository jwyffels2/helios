@echo off
set "WSL_VERSION=2"

set SIGROK_DIR=%ProgramFiles%\sigrok\sigrok-cli
set PULSEVIEW_DIR=%ProgramFiles%\sigrok\PulseView

set SIGROK_EXE=%SIGROK_DIR%\sigrok-cli.exe
set PULSEVIEW_EXE=%PULSEVIEW_DIR%\pulseview.exe

pushd "%~dp0"
:: --- Require Administrator ---
net session >nul 2>&1
if errorlevel 1 (
  echo [ERROR] Please run this script as Administrator.
  exit /b 1
)

:: --- Make sure WSL bits are present (kernel + features) ---
echo [INFO] Ensuring WSL optional components and kernel are installed...
wsl --status >nul 2>&1
if errorlevel 1 (
  echo [INFO] Running: wsl --install --no-distribution
  wsl --install --no-distribution
  if errorlevel 1 (
    echo [ERROR] Failed to install WSL components. Try updating Windows or rebooting.
    exit /b 1
  )
  echo [INFO] WSL components installed. A reboot may be required if this is the first time.
)

:: --- Prefer WSL2 ---
echo [INFO] Setting default WSL version to %WSL_VERSION%...
wsl --update
wsl --set-default-version %WSL_VERSION% >nul 2>&1


:: --- Install Podman ---
winget install --id RedHat.Podman --version 5.6.2 --accept-package-agreements --accept-source-agreements
winget install --id AdaLang.Alire.Portable --version 2.1.0 --accept-package-agreements --accept-source-agreements
winget install --id dorssel.usbipd-win --version 5.3.0 --accept-package-agreements --accept-source-agreements

:: ---------------------------
:: Install sigrok-cli
:: ---------------------------
IF EXIST "%SIGROK_EXE%" (
    echo sigrok-cli already installed
) ELSE (
    echo Downloading sigrok-cli...
    curl -L -o sigrok-cli.exe https://sigrok.org/download/binary/sigrok-cli/sigrok-cli-0.7.2-x86_64-installer.exe

    echo Installing sigrok-cli...
    sigrok-cli.exe /S
    del sigrok-cli.exe
)

:: ---------------------------
:: Install PulseView
:: ---------------------------
IF EXIST "%PULSEVIEW_EXE%" (
    echo PulseView already installed
) ELSE (
    echo Downloading PulseView...
    curl -L -o pulseview.exe https://sigrok.org/download/binary/pulseview/pulseview-0.4.2-64bit-static-release-installer.exe

    echo Installing PulseView...
    pulseview.exe /S
    del pulseview.exe
)

echo.
echo Installation complete
echo Restart terminal to use sigrok-cli

:: ---- Refresh PATH into the *current* cmd.exe ----
for /f "usebackq delims=" %%P in (`
  powershell -NoProfile -Command ^
    "$m=[Environment]::GetEnvironmentVariable('Path','Machine');" ^
    "$u=[Environment]::GetEnvironmentVariable('Path','User');" ^
    "[Environment]::ExpandEnvironmentVariables($m+';'+$u)"
`) do set "PATH=%%P"
rem Now this should work without opening a new window:
alr --non-interactive toolchain --select
popd
pause
