$ErrorActionPreference = "Stop"

$tbDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$rtlDir = Split-Path -Parent $tbDir

function Run-Testbench {
   param(
      [Parameter(Mandatory = $true)]
      [string]$Name,
      [Parameter(Mandatory = $true)]
      [string[]]$Sources
   )

   Write-Host "Running $Name"

   foreach ($src in $Sources) {
      & xvhdl -2008 $src
      if ($LASTEXITCODE -ne 0) {
         throw "xvhdl failed for $src"
      }
   }

   & xelab -debug typical $Name -s "${Name}_sim"
   if ($LASTEXITCODE -ne 0) {
      throw "xelab failed for $Name"
   }

   $logFile = "${Name}.xsim.log"
   if (Test-Path $logFile) {
      Remove-Item -Force $logFile
   }

   & xsim "${Name}_sim" -runall -onfinish quit -log $logFile
   if ($LASTEXITCODE -ne 0) {
      throw "xsim failed for $Name"
   }

   if (Select-String -Quiet -Path $logFile -Pattern "Failure:") {
      throw "Assertions failed in $Name"
   }
}

Push-Location $tbDir
try {
   if (Test-Path "xsim.dir") {
      Remove-Item -Recurse -Force "xsim.dir"
   }
   if (Test-Path "xvhdl.log") {
      Remove-Item -Force "xvhdl.log"
   }
   if (Test-Path "xelab.log") {
      Remove-Item -Force "xelab.log"
   }
   if (Test-Path "xsim.log") {
      Remove-Item -Force "xsim.log"
   }

   Run-Testbench `
      -Name "tb_vram_rgb332_dp" `
      -Sources @(
         (Join-Path $rtlDir "vram_rgb332_dp.vhd"),
         (Join-Path $tbDir "tb_vram_rgb332_dp.vhd")
      )

   Run-Testbench `
      -Name "tb_vram_xbus_slave" `
      -Sources @(
         (Join-Path $rtlDir "vram_rgb332_dp.vhd"),
         (Join-Path $rtlDir "vram_xbus_slave.vhd"),
         (Join-Path $tbDir "tb_vram_xbus_slave.vhd")
      )

   Run-Testbench `
      -Name "tb_vga_scanout_rgb332" `
      -Sources @(
         (Join-Path $rtlDir "vga_640x480_timing.vhd"),
         (Join-Path $rtlDir "vga_scanout_rgb332.vhd"),
         (Join-Path $rtlDir "vram_rgb332_dp.vhd"),
         (Join-Path $tbDir "tb_vga_scanout_rgb332.vhd")
      )

   Write-Host "All XSIM testbenches passed."
}
finally {
   Pop-Location
}
