# Wildfire Risk Prototype

This directory contains a baseline local model for the FIRMS feature join dataset at `C:\Users\Leonard\Desktop\firms_ee_feature_join.csv`.

## What the model does

The dataset appears to contain fire detections that were already matched with environmental features. It does not include explicit non-fire examples, so a true wildfire-occurrence classifier is not possible from this file alone.

The baseline model in this directory therefore predicts a proxy target:

- `1` when FIRMS `confidence >= 80`
- `0` otherwise

That makes the output a **risk proxy for high-confidence detections**, not a calibrated probability that a wildfire exists.

## Features used

The model uses fields that could plausibly be supplied by a weather/environment pipeline:

- latitude / longitude
- surface temperature
- ground heat flux
- canopy surface water
- vegetation type
- vegetation amount
- PDSI
- precipitation
- max and min temperature
- wind components
- derived wind speed
- derived seasonal terms from date

It intentionally excludes `brightness` and `frp` because those are direct detection outputs and would leak the answer.

## Train the model

```powershell
node tools/wildfire-risk/train.js
```

Optional flags:

```powershell
node tools/wildfire-risk/train.js --csv C:\path\to\firms_ee_feature_join.csv --output tools/wildfire-risk/output/model.json
```

## Run inference

Using a JSON payload:

```powershell
node tools/wildfire-risk/predict.js --input tools/wildfire-risk/example_input.json
```

Using CLI values directly:

```powershell
node tools/wildfire-risk/predict.js --lat 48.64 --long -118.37 --date 2026-03-22T18:00:00Z --temperature-surface 289 --tmax 18 --tmin 6 --precipitation 0 --pdsi -3.2 --wind-u 1.8 --wind-v 2.4
```

If a feature is missing, the script imputes the training-set mean and reports which fields were filled that way.

## Run inference from live coordinates

This adapter fetches near-real-time weather fields from Open-Meteo using coordinates, maps them into the model input schema, and then scores the local model.

```powershell
node tools/wildfire-risk/live_adapter.js --lat 48.6411 --long -118.3751
```

You can also test the adapter without network access by replaying a saved API response:

```powershell
node tools/wildfire-risk/live_adapter.js --lat 48.6411 --long -118.3751 --source-file tools/wildfire-risk/sample_open_meteo_response.json
```

Optional output capture:

```powershell
node tools/wildfire-risk/live_adapter.js --lat 48.6411 --long -118.3751 --output tools/wildfire-risk/output/live_result.json
```

The live adapter currently fills:

- latitude / longitude
- timestamp
- surface temperature proxy from current 2 m temperature
- precipitation
- daily max temperature
- daily min temperature
- wind components derived from wind speed and direction

The remaining model fields are imputed from the training-set means because the live weather API does not provide those values directly.

## How to use coordinates with a near-real-time API

The practical path is:

1. Use coordinates to query a weather/environment API.
2. Map the API response into the feature fields expected by `predict.js`.
3. Run inference with the assembled feature payload.

The key fields you need from a live source are:

- current or recent temperature
- precipitation
- wind components or wind speed/direction
- drought proxy if available
- optional vegetation or land-cover context from a static source

If you want a real wildfire probability model instead of this proxy, you will need explicit negative examples or a second dataset containing non-fire coordinate/time samples.
