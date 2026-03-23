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

## True classifier pipeline

There is now a second pipeline that builds a true binary fire-vs-background classifier by generating explicit non-fire negatives.

### How the negatives are built

1. Start from the FIRMS detections as positive examples.
2. Sample background coordinate/time candidates near the same geographic region and season.
3. Reject candidates that are too close to known detections in space or time.
4. Fetch historical weather for both positives and negatives from Open-Meteo archive data.
5. Train a binary classifier on the resulting labeled dataset.

This is a true classifier because it has explicit negative samples, but it is still not field-truth perfect because the negative class is sampled background rather than manually verified non-fire ground truth.

### Build a labeled training dataset

```powershell
node tools/wildfire-risk/build_true_classifier_dataset.js --positives 25 --negatives 25
```

This writes `tools/wildfire-risk/output/true_classifier_dataset.json`.

### Train the true classifier

```powershell
node tools/wildfire-risk/train_true_classifier.js
```

This writes `tools/wildfire-risk/output/true_classifier_model.json`.

### Run live inference with the true classifier

```powershell
node tools/wildfire-risk/live_true_classifier.js --lat 48.6411 --long -118.3751
```

The true classifier currently uses:

- latitude / longitude
- temperature
- relative humidity
- dew point
- precipitation
- max and min daily temperature
- wind components and wind speed
- surface pressure
- cloud cover
- shallow soil temperature
- shallow soil moisture
- seasonal terms from date

### Evaluation split

The true classifier no longer uses a simple time-only split.

- `train`: older samples from seen regions
- `validation`: later samples from seen regions
- `test`: later samples from held-out geographic cells

That makes the final test set harder and reduces the chance that the model is just memorizing local patterns from nearby coordinates.
