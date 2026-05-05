Helios wildfire risk model README
---------------------------------

GitHub repository:
https://github.com/jwyffels2/helios

Branch:
leonard/wildfire-risk-model

This branch adds the wildfire risk model tooling needed for the end project.
The goal is to train a small Node.js classifier from wildfire and weather data,
then score a coordinate with current or replayed weather features.


What this branch includes
-------------------------

The branch includes the final Node true-classifier path:

  tools/wildfire-risk/build_true_classifier_dataset.js
    Builds a labeled dataset from fire detections, non-fire negatives, weather,
    and local context features.

  tools/wildfire-risk/train_true_classifier.js
    Trains the logistic wildfire classifier and writes the model artifact.

  tools/wildfire-risk/live_true_classifier.js
    Scores one latitude and longitude with the trained model.

  tools/wildfire-risk/common.js
    Shared CSV, JSON, math, normalization, imputation, calibration, and
    logistic-regression helpers.

  tools/wildfire-risk/true_classifier_common.js
    Shared feature schema and feature-map construction for the true classifier.

  tools/wildfire-risk/true_classifier_runtime.js
    Shared runtime scoring function used by live inference.

  tools/wildfire-risk/weather_api.js
    Open-Meteo fetch, cache, retry, and weather-to-feature mapping.

  tools/wildfire-risk/context_lookup.js
    Nearest seasonal context lookup for vegetation and drought fields.

  tools/wildfire-risk/output/.gitignore
    Keeps generated datasets, models, API cache files, and scoring output out of
    git.


What was intentionally left out
-------------------------------

The Python comparison model, baseline proxy model, batch demo, PowerShell demo
runner, fixture verifier, and sample replay files are not part of the simplified
main-branch PR. They were useful during exploration, but they are not required
for the end-project runtime path.


How the model works
-------------------

The true classifier is a plain JavaScript logistic-regression model. It uses
explicit fire and non-fire samples rather than treating FIRMS confidence as the
final risk label.

Dataset generation:

  1. Read historical fire/context rows from a local CSV.
  2. Sample positive fire detections.
  3. Generate non-fire negative samples away from known positives.
  4. Fetch historical Open-Meteo archive weather for each sample.
  5. Add static or slowly changing context fields from nearby seasonal rows.
  6. Write tools/wildfire-risk/output/true_classifier_dataset.json.

Training:

  1. Build the numeric feature map.
  2. Impute missing values from training-set feature means.
  3. Normalize features.
  4. Train logistic regression.
  5. Calibrate probabilities on validation data.
  6. Write tools/wildfire-risk/output/true_classifier_model.json.

Live scoring:

  1. Fetch Open-Meteo forecast data for the requested coordinate.
  2. Convert weather fields into model feature names.
  3. Fill vegetation and drought fields from the nearest context row.
  4. Apply the saved imputation, normalization, and calibration values.
  5. Print wildfireProbability as JSON.


Required input data
-------------------

The model needs a local CSV with historical fire detections and context fields.
The final project folder includes this CSV here:

  tools/wildfire-risk/data/firms_ee_feature_join.csv

Set this environment variable only if you want to point at a different CSV
outside the project folder:

  HELIOS_WILDFIRE_CONTEXT_CSV

The CSV should include columns used by the model, including:

  date
  lat
  long
  Temperature_surface
  precipitation
  tmax
  tmin
  Vegetation_Type_surface
  Vegetation_surface
  pdsi
  u-component_of_wind_hybrid
  v-component_of_wind_hybrid


Build the dataset
-----------------

From the repository root:

  node tools/wildfire-risk/build_true_classifier_dataset.js --positives 25 --negatives 25

Useful options:

  --csv path/to/context.csv
  --context-csv path/to/context.csv
  --output tools/wildfire-risk/output/true_classifier_dataset.json
  --fresh
  --resume

The default CSV path is tools/wildfire-risk/data/firms_ee_feature_join.csv.
Passing --csv and --context-csv on the command line overrides the default.


Train the model
---------------

From the repository root:

  node tools/wildfire-risk/train_true_classifier.js

Default input:

  tools/wildfire-risk/output/true_classifier_dataset.json

Default output:

  tools/wildfire-risk/output/true_classifier_model.json


Score one coordinate
--------------------

From the repository root:

  node tools/wildfire-risk/live_true_classifier.js --lat 48.6411 --long -118.3751

Useful options:

  --model tools/wildfire-risk/output/true_classifier_model.json
  --date 2026-05-05T12:00:00Z
  --output tools/wildfire-risk/output/latest_score.json
  --context-csv path/to/context.csv

The output JSON includes:

  coordinates
  rawProbability
  wildfireProbability
  missingFeaturesImputed
  featuresUsed
  targetDescription
  limitation


Important implementation notes
------------------------------

The code uses only built-in Node.js modules. No npm install step is required.

Open-Meteo responses are cached under tools/wildfire-risk/output/cache so
repeat runs do not keep hitting the API.

The model artifact is generated output and is ignored by git. Regenerate it
from the dataset when needed.

The scoring result is a risk estimate, not a confirmed wildfire detection. It
should be treated as a prioritization signal for review.


Future extension points
-----------------------

Good next steps for future students:

  Connect live_true_classifier.js to the ground station so coordinates can be
  scored automatically.

  Replace the local CSV dependency with a committed small fixture or a proper
  data download step if the class wants reproducible training from scratch.

  Add batch scoring only if the final ground-station workflow needs to rank many
  candidate coordinates at once.

  Add a UI layer after the scoring output format is stable.


Troubleshooting
---------------

Dataset build cannot find the CSV:

  Confirm tools/wildfire-risk/data/firms_ee_feature_join.csv is present, or set
  HELIOS_WILDFIRE_CONTEXT_CSV, or pass --csv and --context-csv.

Live scoring cannot find the model:

  Run train_true_classifier.js first or pass --model with the correct path.

Weather API calls fail:

  Rerun later, or check tools/wildfire-risk/output/cache for cached responses.

Many features are imputed:

  Confirm the context CSV has the expected vegetation, drought, wind, and
  temperature columns.
