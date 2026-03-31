Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$containerImage = "localhost/helios-build:latest"
$workspaceTests = "/workspace/tests"
$outputExe = Join-Path $repoRoot "tests\bin\tests.exe"
$minTargetDir = Join-Path $repoRoot "third_party\min\target"

if (-not (Test-Path $minTargetDir)) {
  Write-Host "Initializing third_party/min submodule..."
  git submodule update --init --recursive third_party/min
  if ($LASTEXITCODE -ne 0) {
    throw "Failed to initialize third_party/min"
  }
}

Write-Host "Starting Podman machine if needed..."
$podmanStartOutput = & podman machine start 2>&1
$podmanStartExitCode = $LASTEXITCODE
$podmanStartOutput | Out-Host
if ($podmanStartExitCode -ne 0) {
  Write-Warning "podman machine start returned a non-zero exit code; continuing and letting the build verify whether Podman is usable."
}

$buildCommand = @"
alr build &&
riscv64-elf-objcopy -O binary bin/tests bin/tests.bin &&
truncate -s %4 bin/tests.bin &&
gcc /workspace/third_party/helios-neorv32-setups/neorv32/sw/image_gen/image_gen.c -o /tmp/image_gen &&
/tmp/image_gen -i bin/tests.bin -o bin/tests.exe -t app_bin
"@

Write-Host "Building framebuffer demo application..."
podman run --rm `
  -v "${repoRoot}:/workspace" `
  -w $workspaceTests `
  $containerImage `
  bash -lc $buildCommand
if ($LASTEXITCODE -ne 0) {
  throw "Framebuffer demo build failed"
}

if (-not (Test-Path $outputExe)) {
  throw "Framebuffer demo image was not generated at $outputExe"
}

Write-Host "Framebuffer demo image ready at: $outputExe"
