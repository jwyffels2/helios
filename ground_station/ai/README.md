# AI Model Container

This directory contains Justin's Python/Poetry container setup for AI model work.

The existing wildfire pipeline in `tools/wildfire-risk` remains the Node.js
baseline. The Python script here trains a second model from the same generated
dataset so its metrics can be compared against that baseline.

## Build and enter the container

From the repository root:

```powershell
podman build -t helios-ai-model -f .\ground_station\ai\ai_model.dockerfile .\ground_station\ai
podman run -it --rm -v "${PWD}:/workspace" -w /workspace/ground_station/ai helios-ai-model bash
```

Inside the container:

```bash
poetry install
```

## Train the Node baseline

From the repository root:

```powershell
node .\tools\wildfire-risk\train_true_classifier.js
```

That writes `tools/wildfire-risk/output/true_classifier_model.json`.

## Train the Python comparison model

Inside the Python container, from `/workspace/ground_station/ai`:

```bash
poetry run python train_wildfire_model.py
```

That reads:

```text
tools/wildfire-risk/output/true_classifier_dataset.json
```

and writes:

```text
ground_station/ai/output/wildfire_model_python.json
```

By default the script trains both:

- `linear`: a Python logistic regression baseline
- `expanded`: logistic regression with squared and interaction features
- `sklearn-logistic`: scikit-learn logistic regression with interaction features
- `random-forest`: scikit-learn random forest
- `extra-trees`: scikit-learn extremely randomized trees
- `hist-gradient-boosting`: scikit-learn histogram gradient boosting

Tree-based candidates use `CalibratedClassifierCV` with sigmoid calibration by
default, so the reported probabilities are calibrated instead of raw
`predict_proba` scores. It selects the model with the lowest calibrated
validation log loss and reports validation/test AUC, log loss, and Brier score.

Calibration controls:

```bash
poetry run python train_wildfire_model.py --calibration-cv 5 --calibration-method sigmoid
```

If you intentionally want to train on an in-progress checkpointed dataset:

```bash
poetry run python train_wildfire_model.py --allow-partial
```

## Why this helps

The Node model is the stable baseline. The Python model uses the same labels and
split strategy but can add nonlinear feature interactions, which gives the team a
more capable comparison path without throwing away the existing work.
