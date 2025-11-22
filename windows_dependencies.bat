@echo off
set "WSL_VERSION=2"
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

:: ---- Refresh PATH into the *current* cmd.exe ----
for /f "usebackq delims=" %%P in (`
  powershell -NoProfile -Command ^
    "$m=[Environment]::GetEnvironmentVariable('Path','Machine');" ^
    "$u=[Environment]::GetEnvironmentVariable('Path','User');" ^
    "[Environment]::ExpandEnvironmentVariables($m+';'+$u)"
`) do set "PATH=%%P"
rem Now this should work without opening a new window:
alr --non-interactive toolchain --select
