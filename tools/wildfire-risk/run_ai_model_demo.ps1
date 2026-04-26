param(
  # Existing artifacts are passed in by path so the same script can run a small
  # smoke dataset, a full demo dataset, or a future dataset without edits.
  [string]$DatasetPath = "tools/wildfire-risk/output/true_classifier_dataset.json",
  [string]$NodeModelPath = "tools/wildfire-risk/output/true_classifier_model.json",
  [string]$PythonModelPath = "ground_station/ai/output/wildfire_model_python.json",
  [string]$BatchInputPath = "tools/wildfire-risk/batch_example.csv",
  [string]$SummaryPath = "tools/wildfire-risk/output/ai_model_demo_summary.txt",
  # AllowPartial is intentionally opt-in. The default behavior refuses to train
  # on checkpointed/incomplete data so demo metrics are not accidentally quoted
  # from a half-built dataset.
  [switch]$AllowPartial,
  [switch]$SkipNodeTrain,
  [switch]$SkipPythonTrain,
  [switch]$SkipContainerBuild,
  [switch]$SkipBatchScore,
  [switch]$UseLiveWeather
)

$ErrorActionPreference = "Stop"

function Invoke-Step {
  param(
    [Parameter(Mandatory = $true)][string]$Exe,
    [Parameter(Mandatory = $true)][string[]]$Args,
    [Parameter(Mandatory = $true)][string]$Label
  )

  # Standard wrapper for external command steps so failures stop the demo early.
  Write-Host ""
  Write-Host "==> $Label"
  & $Exe @Args
  if ($LASTEXITCODE -ne 0) {
    throw "Step failed: $Label"
  }
}

function Resolve-RepoRoot {
  # Resolve repo root relative to this script so it can run from any CWD.
  $scriptPath = $PSCommandPath
  if (-not $scriptPath) {
    $scriptPath = $MyInvocation.MyCommand.Definition
  }
  $scriptDir = Split-Path -Parent $scriptPath
  return (Resolve-Path (Join-Path $scriptDir "..\..")).Path
}

function Get-JsonFile {
  # Helper to read typed JSON objects from artifact files.
  param([Parameter(Mandatory = $true)][string]$Path)
  return (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json)
}

function Get-PodmanMachineState {
  # Best-effort probe for local Podman machine state.
  param([string]$MachineName = "podman-machine-default")

  $previous = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try {
    $stateOutput = & podman machine inspect $MachineName --format "{{.State}}" 2>$null
    $exitCode = $LASTEXITCODE
  }
  finally {
    $ErrorActionPreference = $previous
  }

  if ($exitCode -ne 0 -or -not $stateOutput) {
    return $null
  }

  return ([string]($stateOutput | Select-Object -First 1)).Trim()
}

function Ensure-PodmanReady {
  # Ensure container runtime is available before Python training steps.
  param([string]$MachineName = "podman-machine-default")

  $state = Get-PodmanMachineState -MachineName $MachineName
  if ($state -ne "Running") {
    Write-Host ""
    Write-Host "==> Start Podman machine ($MachineName)"
    & podman machine start $MachineName
    if ($LASTEXITCODE -ne 0) {
      throw "Could not start Podman machine '$MachineName'. If it does not exist, run: podman machine init"
    }
  }

  $previous = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try {
    & podman info *> $null
    $exitCode = $LASTEXITCODE
  }
  finally {
    $ErrorActionPreference = $previous
  }

  if ($exitCode -ne 0) {
    throw "Podman is not ready. Check 'podman system connection list' and ensure '$MachineName' is reachable."
  }
}

$repoRoot = Resolve-RepoRoot
Push-Location $repoRoot
try {
  # Guard against accidental training on incomplete datasets.
  if (-not (Test-Path -LiteralPath $DatasetPath)) {
    throw "Dataset not found: $DatasetPath. Build it first with tools/wildfire-risk/build_true_classifier_dataset.js."
  }

  $dataset = Get-JsonFile -Path $DatasetPath
  if (($dataset.status -ne "complete") -and (-not $AllowPartial)) {
    throw "Dataset status is '$($dataset.status)'. Re-run with -AllowPartial if you intentionally want a demo on in-progress data."
  }

  if (-not $SkipNodeTrain) {
    # Train the Node baseline model artifact.
    $nodeArgs = @("tools/wildfire-risk/train_true_classifier.js", "--input", $DatasetPath, "--output", $NodeModelPath)
    if ($AllowPartial) {
      $nodeArgs += "--allow-partial"
    }
    Invoke-Step -Exe "node" -Args $nodeArgs -Label "Train Node baseline model"
  }

  if (-not $SkipPythonTrain) {
    # Train the Python comparison model inside the pinned AI container image.
    # Keeping Python in a container avoids requiring every teammate to install
    # Poetry/scikit-learn directly on Windows.
    Ensure-PodmanReady

    if (-not $SkipContainerBuild) {
      Invoke-Step -Exe "podman" -Args @(
        "build",
        "-t", "helios-ai-model",
        "-f", ".\ground_station\ai\ai_model.dockerfile",
        ".\ground_station\ai"
      ) -Label "Build Python AI container image"
    }

    $containerCommand = "poetry install --no-root && poetry run python train_wildfire_model.py --input /workspace/$($DatasetPath -replace '\\','/') --output /workspace/$($PythonModelPath -replace '\\','/')"
    if ($AllowPartial) {
      $containerCommand += " --allow-partial"
    }

    Invoke-Step -Exe "podman" -Args @(
      "run",
      "--rm",
      "-v", "${repoRoot}:/workspace",
      "-w", "/workspace/ground_station/ai",
      "helios-ai-model",
      "bash", "-lc", $containerCommand
    ) -Label "Train Python comparison model"
  }

  if (-not $SkipBatchScore) {
    # Run a demo batch scoring pass and generate ranked output artifacts.
    $batchArgs = @(
      "tools/wildfire-risk/batch_live_true_classifier.js",
      "--input", $BatchInputPath,
      "--model", $NodeModelPath,
      "--output-csv", "tools/wildfire-risk/output/batch_scores_demo.csv",
      "--output-json", "tools/wildfire-risk/output/batch_scores_demo.json"
    )
    if (-not $UseLiveWeather) {
      $batchArgs += @("--source-file", "tools/wildfire-risk/sample_open_meteo_response.json")
    }
    Invoke-Step -Exe "node" -Args $batchArgs -Label "Run batch demo scoring"
  }

  if (-not (Test-Path -LiteralPath $NodeModelPath)) {
    throw "Node model output missing: $NodeModelPath"
  }
  if (-not (Test-Path -LiteralPath $PythonModelPath)) {
    throw "Python model output missing: $PythonModelPath"
  }

  $nodeModel = Get-JsonFile -Path $NodeModelPath
  $pythonModel = Get-JsonFile -Path $PythonModelPath

  $selectedMode = [string]$pythonModel.selectedMode
  $selectedMetricsProp = $pythonModel.metrics.PSObject.Properties[$selectedMode]
  if ($null -eq $selectedMetricsProp) {
    throw "Could not find metrics for selected Python mode '$selectedMode'."
  }
  $selectedMetrics = $selectedMetricsProp.Value

  $nodeTestCal = $nodeModel.metrics.test.calibrated
  $pythonTestCal = $selectedMetrics.test.calibrated

  $summaryLines = @(
    # Keep the final summary plain text so it is easy to paste into slides,
    # meeting notes, or the terminal without needing a JSON viewer.
    "Wildfire AI Demo Summary",
    "GeneratedAt: $(Get-Date -Format o)",
    "",
    "Dataset",
    "  path: $DatasetPath",
    "  status: $($dataset.status)",
    "  samples: $($dataset.samples.Count)",
    "",
    "Node baseline model",
    "  path: $NodeModelPath",
    "  test_calibrated_auc: $([double]$nodeTestCal.auc)",
    "  test_calibrated_log_loss: $([double]$nodeTestCal.logLoss)",
    "  test_calibrated_brier: $([double]$nodeTestCal.brierScore)",
    "",
    "Python comparison model",
    "  path: $PythonModelPath",
    "  selected_mode: $selectedMode",
    "  test_calibrated_auc: $([double]$pythonTestCal.auc)",
    "  test_calibrated_log_loss: $([double]$pythonTestCal.logLoss)",
    "  test_calibrated_brier: $([double]$pythonTestCal.brierScore)",
    "",
    "Demo artifacts",
    "  tools/wildfire-risk/output/batch_scores_demo.csv",
    "  tools/wildfire-risk/output/batch_scores_demo.json",
    "  tools/wildfire-risk/output/potential_wildfires.txt",
    "  tools/wildfire-risk/output/potential_wildfires_globe.html"
  )

  $summaryDir = Split-Path -Parent $SummaryPath
  if ($summaryDir -and -not (Test-Path -LiteralPath $summaryDir)) {
    New-Item -ItemType Directory -Path $summaryDir | Out-Null
  }

  Set-Content -LiteralPath $SummaryPath -Value $summaryLines -Encoding UTF8
  Write-Host ""
  Write-Host "Demo complete."
  Write-Host "Summary written to $SummaryPath"
}
finally {
  Pop-Location
}
