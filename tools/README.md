# Tools Documentation

This is the single documentation entry point for tool-side wildfire AI work.
It replaces per-folder AI README files.

## Scope

- `tools/wildfire-risk`: Node.js data, training, inference, and demo scripts.
- `ground_station/ai`: Python containerized comparison model trained from the same dataset.

## Quick Start (One Command Demo)

From repository root:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\wildfire-risk\run_ai_model_demo.ps1
```

This run will:

- validate dataset status
- train the Node true-classifier model
- train the Python comparison model in container
- run batch scoring
- write summary/artifacts in `tools/wildfire-risk/output`

Useful flags:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\wildfire-risk\run_ai_model_demo.ps1 -AllowPartial
powershell -ExecutionPolicy Bypass -File .\tools\wildfire-risk\run_ai_model_demo.ps1 -SkipContainerBuild
powershell -ExecutionPolicy Bypass -File .\tools\wildfire-risk\run_ai_model_demo.ps1 -UseLiveWeather
```

## Node Pipeline (tools/wildfire-risk)

Baseline proxy model:

```powershell
node tools/wildfire-risk/train.js
node tools/wildfire-risk/predict.js --input tools/wildfire-risk/example_input.json
node tools/wildfire-risk/live_adapter.js --lat 48.6411 --long -118.3751
```

True classifier dataset + model:

```powershell
node tools/wildfire-risk/build_true_classifier_dataset.js --positives 25 --negatives 25
node tools/wildfire-risk/train_true_classifier.js
node tools/wildfire-risk/verify_true_classifier_fixture.js
```

Live and batch inference:

```powershell
node tools/wildfire-risk/live_true_classifier.js --lat 48.6411 --long -118.3751
node tools/wildfire-risk/batch_live_true_classifier.js --input tools/wildfire-risk/batch_example.csv --output-csv tools/wildfire-risk/output/batch_scores.csv
```

Offline replay for deterministic testing:

```powershell
node tools/wildfire-risk/live_true_classifier.js --lat 48.6411 --long -118.3751 --source-file tools/wildfire-risk/sample_open_meteo_response.json
node tools/wildfire-risk/batch_live_true_classifier.js --input tools/wildfire-risk/batch_example.csv --source-file tools/wildfire-risk/sample_open_meteo_response.json
```

## Python Comparison Model (ground_station/ai)

Build and run container from repo root:

```powershell
podman build -t helios-ai-model -f .\ground_station\ai\ai_model.dockerfile .\ground_station\ai
podman run -it --rm -v "${PWD}:/workspace" -w /workspace/ground_station/ai helios-ai-model bash
```

Inside container:

```bash
poetry install
poetry run python train_wildfire_model.py
```

Python artifact output:

- `ground_station/ai/output/wildfire_model_python.json`

Input dataset shared with Node pipeline:

- `tools/wildfire-risk/output/true_classifier_dataset.json`

## Outputs You Should Expect

- `tools/wildfire-risk/output/true_classifier_dataset.json`
- `tools/wildfire-risk/output/true_classifier_model.json`
- `tools/wildfire-risk/output/batch_scores_demo.csv`
- `tools/wildfire-risk/output/batch_scores_demo.json`
- `tools/wildfire-risk/output/potential_wildfires.txt`
- `tools/wildfire-risk/output/potential_wildfires_globe.html`
- `tools/wildfire-risk/output/ai_model_demo_summary.txt`

## Model Notes

- Baseline Node model is a confidence proxy from detections.
- True classifier adds explicit background negatives.
- Python model is a comparison path trained on the same generated dataset.
- Calibration metrics (AUC, log loss, Brier) are reported for validation/test.
