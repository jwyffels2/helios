$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object Security.Principal.WindowsPrincipal($id)
    $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Pause-Continue {
    Write-Host ""
    Read-Host "Press Enter to continue"
}

function Get-VidPid([string]$InstanceId) {
    if ($InstanceId -match 'VID_([0-9A-Fa-f]{4})&PID_([0-9A-Fa-f]{4})') {
        return ("{0}:{1}" -f $matches[1].ToUpper(), $matches[2].ToUpper())
    }
    ""
}

function Get-DeviceState($d) {
    if (-not [string]::IsNullOrWhiteSpace($d.ClientIPAddress)) { return "Attached" }
    if (-not [string]::IsNullOrWhiteSpace($d.PersistedGuid))   { return "Shared" }
    return "Not shared"
}

function Get-UsbDeviceInstanceID([string]$InstanceId) {
    if ([string]::IsNullOrWhiteSpace($InstanceId)) { return "" }

    $parts = $InstanceId -split '\\'
    if ($parts.Count -lt 3) { return "" }

    $candidate = $parts[-1].Trim()

    # These are usually location-based IDs, not real serial/device IDs.
    if ($candidate -match '^\d+&[0-9A-Fa-f]+&\d+&\d+$') { return "" }
    if ($candidate -match '^ROOT_') { return "" }

    return $candidate
}

function Get-UsbDevices {
    $state = (& usbipd.exe state | Out-String) | ConvertFrom-Json
    $i = 0
    @($state.Devices) | ForEach-Object {
        $obj = [pscustomobject]@{
            Index            = $i
            BusId            = $_.BusId
            VidPid           = Get-VidPid $_.InstanceId
            DeviceInstanceID = Get-UsbDeviceInstanceID $_.InstanceId
            Device           = $_.Description
            State            = Get-DeviceState $_
            InstanceId       = $_.InstanceId
        }
        $i++
        $obj
    }
}

function Show-DeviceList([array]$Devices) {
    Write-Host ""
    Write-Host "Devices"
    Write-Host "------------------------------------------------------------------------------------------"

    $Devices |
        Select-Object `
            @{Name='Index';Expression={$_.Index}},
            @{Name='BusId';Expression={$_.BusId}},
            @{Name='VidPid';Expression={$_.VidPid}},
            @{Name='DeviceInstanceID';Expression={
                if ([string]::IsNullOrWhiteSpace($_.DeviceInstanceID)) { "-" }
                elseif ($_.DeviceInstanceID.Length -gt 22) { $_.DeviceInstanceID.Substring(0,19) + '...' }
                else { $_.DeviceInstanceID }
            }},
            @{Name='Device';Expression={
                if ($_.Device.Length -gt 40) { $_.Device.Substring(0,37) + '...' }
                else { $_.Device }
            }},
            @{Name='State';Expression={$_.State}} |
        Format-Table -AutoSize
}

function Show-Menu([array]$Devices) {
    Write-Host ""
    Write-Host "==============================================================="
    Write-Host "                   usbipd / WSL Helper Menu"
    Write-Host "==============================================================="
    Show-DeviceList $Devices
    Write-Host ""
    Write-Host "Commands:"
    Write-Host "  l             List Windows USB devices"
    Write-Host "  b 0,2         Bind device(s)"
    Write-Host "  a 0,2         Attach device(s) to WSL"
    Write-Host "  d 1           Detach device(s) from WSL"
    Write-Host "  u 1           Unbind device(s)"
    Write-Host "  w             List attached WSL devices"
    Write-Host "  r             Refresh"
    Write-Host "  q             Done"
    Write-Host "==============================================================="
}

function Parse-Indexes([string]$Text, [array]$Devices) {
    if ([string]::IsNullOrWhiteSpace($Text)) { return @() }
    $nums = @(
        $Text -split ',' |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ -match '^\d+$' } |
        ForEach-Object { [int]$_ }
    )
    @($Devices | Where-Object { $nums -contains $_.Index })
}

function Invoke-DeviceAction([string]$Verb, [array]$Selected) {
    foreach ($d in $Selected) {
        switch ($Verb) {
            "b" {
                if ($d.State -ne "Not shared") {
                    Write-Host "Skipping $($d.Index): already $($d.State)"
                    continue
                }
                Write-Host "Binding $($d.BusId)..."
                usbipd.exe bind --busid $d.BusId
            }
            "a" {
                if ($d.State -eq "Attached") {
                    Write-Host "Skipping $($d.Index): already Attached"
                    continue
                }
                Write-Host "Attaching $($d.BusId)..."
                usbipd.exe attach --wsl --busid $d.BusId
            }
            "d" {
                if ($d.State -ne "Attached") {
                    Write-Host "Skipping $($d.Index): not Attached"
                    continue
                }
                Write-Host "Detaching $($d.BusId)..."
                usbipd.exe detach --busid $d.BusId
            }
            "u" {
                if ($d.State -notin @("Shared","Attached")) {
                    Write-Host "Skipping $($d.Index): not Shared/Attached"
                    continue
                }
                Write-Host "Unbinding $($d.BusId)..."
                usbipd.exe unbind --busid $d.BusId
            }
        }
    }
}

if (-not (Test-IsAdmin)) {
    Write-Host ""
    Write-Host "========================================================="
    Write-Host " Warning: not running as Administrator."
    Write-Host " Bind / Unbind may fail unless this window is elevated."
    Write-Host "========================================================="
    Pause-Continue
}

while ($true) {
    $devices = Get-UsbDevices
    Show-Menu $devices
    $inputLine = Read-Host "Enter command"

    if ($inputLine -match '^\s*q\s*$') { break }
    if ($inputLine -match '^\s*r\s*$') { continue }

    if ($inputLine -match '^\s*l\s*$') {
        usbipd.exe list
        Pause-Continue
        continue
    }

    if ($inputLine -match '^\s*w\s*$') {
        wsl ./shared_usb_devices.sh
        Pause-Continue
        continue
    }

    if ($inputLine -match '^\s*([badu])\s+(.+)$') {
        $verb = $matches[1]
        $selected = Parse-Indexes $matches[2] $devices

        if (-not $selected) {
            Write-Host "No valid device indexes selected."
            Pause-Continue
            continue
        }

        Invoke-DeviceAction $verb $selected

        if ($verb -eq "a") {
            Write-Host ""
            Write-Host "WSL devices after attach:"
            Write-Host "---------------------------------------------------------"
            wsl ./shared_usb_devices.sh
        }

        Pause-Continue
        continue
    }

    Write-Host "Invalid command."
    Pause-Continue
}

Write-Host ""
Write-Host "Done."
