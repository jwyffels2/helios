@echo off
setlocal ENABLEDELAYEDEXPANSION

:: =========================
:: Config (edit if you want)
:: =========================
set "DISTRO_NAME=Ubuntu-25.04"
set "WSL_VERSION=2"
set "URL=https://releases.ubuntu.com/plucky/ubuntu-25.04-wsl-amd64.wsl"
set "FILENAME=ubuntu-25.04-wsl-amd64.wsl"
set "DOWNLOAD_DIR=%TEMP%\wsl-downloads"
set "INSTALL_DIR=%LOCALAPPDATA%\WSL\%DISTRO_NAME%"
:: =========================

title Install %DISTRO_NAME% for WSL

echo.
echo === %DISTRO_NAME% (WSL%WSL_VERSION%) Installer ===
echo.

:: --- Require Administrator ---
net session >nul 2>&1
if errorlevel 1 (
  echo [ERROR] Please run this script as Administrator.
  exit /b 1
)

:: --- Create working folders ---
if not exist "%DOWNLOAD_DIR%" mkdir "%DOWNLOAD_DIR%" >nul 2>&1
if not exist "%DOWNLOAD_DIR%" (
  echo [ERROR] Unable to create download directory: "%DOWNLOAD_DIR%"
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
wsl --set-default-version %WSL_VERSION% >nul 2>&1

:: --- Download the image (.wsl) ---
set "DEST=%DOWNLOAD_DIR%\%FILENAME%"
if exist "%DEST%" (
  echo [INFO] Found existing download at: "%DEST%"
) else (
  echo [INFO] Downloading image:
  echo        %URL%
  where curl >nul 2>&1
  if not errorlevel 1 (
    curl -L -o "%DEST%" "%URL%"
  ) else (
    :: Fallback to PowerShell if curl isn't available
    powershell -NoLogo -NoProfile -Command ^
      "try { Invoke-WebRequest -Uri '%URL%' -OutFile '%DEST%' -UseBasicParsing } catch { exit 1 }"
  )
  if errorlevel 1 (
    echo [ERROR] Download failed.
    exit /b 1
  )
)
for %%I in ("%DEST%") do set "SIZE=%%~zI"
echo [INFO] Download complete: %DEST%  (%SIZE% bytes)

:: --- Stop any running WSL instances to avoid file locks ---
echo [INFO] Shutting down any running WSL instances...
wsl --shutdown >nul 2>&1

:: --- Abort if the distro name already exists ---
for /f "tokens=*" %%D in ('wsl --list --quiet 2^>nul') do (
  if /I "%%~D"=="%DISTRO_NAME%" (
    echo [ERROR] A distro named "%DISTRO_NAME%" is already registered.
    echo         If you want to replace it, first export/backup and unregister it with:
    echo         wsl --export "%DISTRO_NAME%" "%USERPROFILE%\Desktop\%DISTRO_NAME%.tar"
    echo         wsl --unregister "%DISTRO_NAME%"
    exit /b 1
  )
)

:: --- Create install dir ---
if not exist "%INSTALL_DIR%" mkdir "%INSTALL_DIR%" >nul 2>&1
if not exist "%INSTALL_DIR%" (
  echo [ERROR] Unable to create install directory: "%INSTALL_DIR%"
  exit /b 1
)

echo [INFO] Importing distro...
echo         Name : %DISTRO_NAME%
echo         Root : %INSTALL_DIR%
echo         File : %DEST%

:: Note: wsl --import supports .tar (and other WSL exports). Many .wsl bundles also import via --import.
:: We try import first; if it fails, we try import-in-place (for .vhdx-style bundles).
wsl --import "%DISTRO_NAME%" "%INSTALL_DIR%" "%DEST%" --version %WSL_VERSION%
if errorlevel 1 (
  echo [WARN] Standard import failed, attempting "import-in-place" ^(valid for .vhdx-based bundles^)^...
  wsl --import-in-place "%DISTRO_NAME%" "%DEST%"
  if errorlevel 1 (
    echo [ERROR] Import failed. The file may not be a supported archive/bundle for this Windows/WSL version.
    exit /b 1
  )
)

echo [INFO] Import completed successfully.

:: --- Make it the default (optional) ---
wsl --set-default "%DISTRO_NAME%" >nul 2>&1

:: --- First launch hint ---
echo.
echo [NEXT] Launch your new distro with:
echo        wsl -d "%DISTRO_NAME%"
echo.
echo       On first run, you may be prompted to create a Unix user.
echo.

echo [DONE] %DISTRO_NAME% is installed.
exit /b 0
