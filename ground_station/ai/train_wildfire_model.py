"""Train a Python wildfire classifier from the generated Node dataset.

This keeps the existing Node.js wildfire pipeline as the baseline while using
Justin's Python/Poetry container to try a stronger nonlinear tabular model.
"""

from __future__ import annotations

import argparse
import json
import math
from collections import Counter
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import numpy as np
import pandas as pd

try:
    from sklearn.base import clone
    from sklearn.calibration import CalibratedClassifierCV
    from sklearn.ensemble import ExtraTreesClassifier, HistGradientBoostingClassifier, RandomForestClassifier
    from sklearn.linear_model import LogisticRegression
    from sklearn.metrics import roc_auc_score
    from sklearn.pipeline import make_pipeline
    from sklearn.preprocessing import PolynomialFeatures, StandardScaler

    SKLEARN_AVAILABLE = True
except ImportError:
    SKLEARN_AVAILABLE = False


REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_DATASET = REPO_ROOT / "tools" / "wildfire-risk" / "output" / "true_classifier_dataset.json"
DEFAULT_OUTPUT = Path(__file__).resolve().parent / "output" / "wildfire_model_python.json"

FEATURE_NAMES = [
    # This list must stay aligned with tools/wildfire-risk/true_classifier_common.js.
    # The Python comparison model reads the Node-generated dataset and evaluates
    # different model families on the same feature contract.
    "lat",
    "long",
    "elevation",
    "temperatureSurface",
    "relativeHumiditySurface",
    "dewPointSurface",
    "precipitation",
    "tmax",
    "tmin",
    "vegetationType",
    "vegetation",
    "pdsi",
    "windU",
    "windV",
    "surfacePressure",
    "cloudCover",
    "soilTemperatureSurface",
    "soilMoistureSurface",
    "temperature24hAvg",
    "temperature72hAvg",
    "humidity24hAvg",
    "humidity72hAvg",
    "precipitation72hTotal",
    "precipitation7dTotal",
    "windSpeed7dMax",
    "soilMoisture72hAvg",
    "soilMoisture7dAvg",
    "soilTemperature7dAvg",
    "windSpeed",
    "dayOfYearSin",
    "dayOfYearCos",
]

INTERACTION_PAIRS = [
    # Manual interaction terms for the "expanded" logistic candidate. These are
    # domain-shaped pairs where combined effects matter, such as heat + humidity
    # or temperature + drought. Tree models learn interactions internally.
    ("lat", "long"),
    ("temperatureSurface", "relativeHumiditySurface"),
    ("temperatureSurface", "precipitation"),
    ("temperatureSurface", "pdsi"),
    ("temperatureSurface", "windSpeed"),
    ("temperature72hAvg", "humidity72hAvg"),
    ("temperature72hAvg", "precipitation7dTotal"),
    ("temperature72hAvg", "soilMoisture7dAvg"),
    ("relativeHumiditySurface", "windSpeed"),
    ("humidity72hAvg", "windSpeed7dMax"),
    ("precipitation", "pdsi"),
    ("precipitation7dTotal", "pdsi"),
    ("precipitation7dTotal", "soilMoisture7dAvg"),
    ("vegetation", "pdsi"),
    ("vegetation", "soilMoisture7dAvg"),
    ("elevation", "temperatureSurface"),
    ("cloudCover", "relativeHumiditySurface"),
    ("soilMoistureSurface", "temperatureSurface"),
    ("dayOfYearSin", "temperatureSurface"),
    ("dayOfYearCos", "temperatureSurface"),
    ("dayOfYearSin", "relativeHumiditySurface"),
    ("dayOfYearCos", "precipitation"),
]


@dataclass
class Split:
    """Container for the time/geography split used by every candidate model."""

    training: pd.DataFrame
    validation: pd.DataFrame
    test: pd.DataFrame
    held_out_regions: list[str]


@dataclass
class FittedModel:
    """Serializable summary of one trained candidate and its metrics."""

    mode: str
    feature_names: list[str]
    weights: np.ndarray | None
    bias: float | None
    calibration: dict[str, Any]
    validation: dict[str, Any]
    test: dict[str, Any]
    sklearn_estimator: str | None = None


def parse_args() -> argparse.Namespace:
    """Parse CLI options for dataset path, split policy, and model family."""
    parser = argparse.ArgumentParser(
        description="Train a Python wildfire model from tools/wildfire-risk generated data."
    )
    parser.add_argument("--input", default=str(DEFAULT_DATASET), help="Path to true_classifier_dataset.json")
    parser.add_argument("--output", default=str(DEFAULT_OUTPUT), help="Output JSON model artifact path")
    parser.add_argument("--allow-partial", action="store_true", help="Allow training from an in-progress dataset")
    parser.add_argument("--epochs", type=int, default=900)
    parser.add_argument("--learning-rate", type=float, default=0.04)
    parser.add_argument("--l2-penalty", type=float, default=0.001)
    parser.add_argument("--test-time-ratio", type=float, default=0.2)
    parser.add_argument("--test-region-ratio", type=float, default=0.25)
    parser.add_argument("--validation-time-ratio", type=float, default=0.2)
    parser.add_argument("--geo-cell-degrees", type=float, default=2.0)
    parser.add_argument("--calibration-cv", type=int, default=3, help="Cross-validation folds for tree model calibration")
    parser.add_argument("--calibration-method", choices=["sigmoid", "isotonic"], default="sigmoid")
    parser.add_argument(
        "--model",
        choices=[
            "auto",
            "linear",
            "expanded",
            "sklearn-logistic",
            "random-forest",
            "extra-trees",
            "hist-gradient-boosting",
        ],
        default="auto",
        help="auto trains all available candidates, then selects by validation log loss.",
    )
    return parser.parse_args()


def parse_number(value: Any) -> float | None:
    """Return a finite float or None for missing/invalid inputs."""
    if value is None or value == "":
        return None
    try:
        number = float(value)
    except (TypeError, ValueError):
        return None
    if math.isnan(number) or math.isinf(number):
        return None
    return number


def parse_date(value: Any) -> datetime:
    """Parse ISO-like timestamps and normalize to UTC."""
    if isinstance(value, str):
        text = value.replace("Z", "+00:00")
        try:
            parsed = datetime.fromisoformat(text)
            if parsed.tzinfo is None:
                return parsed.replace(tzinfo=timezone.utc)
            return parsed.astimezone(timezone.utc)
        except ValueError:
            pass
    return datetime.now(timezone.utc)


def day_of_year(date_value: datetime) -> int:
    """UTC day-of-year for seasonal feature encoding."""
    return int(date_value.strftime("%j"))


def pick(sample: dict[str, Any], *keys: str) -> float | None:
    """Return the first finite numeric value among candidate keys."""
    for key in keys:
        number = parse_number(sample.get(key))
        if number is not None:
            return number
    return None


def build_feature_map(sample: dict[str, Any]) -> dict[str, float | None]:
    """Build the canonical feature dictionary from a raw sample record."""
    feature_map = {
        "lat": pick(sample, "lat"),
        "long": pick(sample, "long"),
        "elevation": pick(sample, "elevation"),
        "temperatureSurface": pick(sample, "temperatureSurface", "Temperature_surface"),
        "relativeHumiditySurface": pick(sample, "relativeHumiditySurface", "relative_humidity_2m"),
        "dewPointSurface": pick(sample, "dewPointSurface", "dew_point_2m"),
        "precipitation": pick(sample, "precipitation"),
        "tmax": pick(sample, "tmax"),
        "tmin": pick(sample, "tmin"),
        "vegetationType": pick(sample, "vegetationType", "Vegetation_Type_surface"),
        "vegetation": pick(sample, "vegetation", "Vegetation_surface"),
        "pdsi": pick(sample, "pdsi"),
        "windU": pick(sample, "windU", "u-component_of_wind_hybrid"),
        "windV": pick(sample, "windV", "v-component_of_wind_hybrid"),
        "surfacePressure": pick(sample, "surfacePressure", "surface_pressure"),
        "cloudCover": pick(sample, "cloudCover", "cloud_cover"),
        "soilTemperatureSurface": pick(sample, "soilTemperatureSurface", "soil_temperature_0_to_7cm"),
        "soilMoistureSurface": pick(sample, "soilMoistureSurface", "soil_moisture_0_to_7cm"),
        "temperature24hAvg": pick(sample, "temperature24hAvg"),
        "temperature72hAvg": pick(sample, "temperature72hAvg"),
        "humidity24hAvg": pick(sample, "humidity24hAvg"),
        "humidity72hAvg": pick(sample, "humidity72hAvg"),
        "precipitation72hTotal": pick(sample, "precipitation72hTotal"),
        "precipitation7dTotal": pick(sample, "precipitation7dTotal"),
        "windSpeed7dMax": pick(sample, "windSpeed7dMax"),
        "soilMoisture72hAvg": pick(sample, "soilMoisture72hAvg"),
        "soilMoisture7dAvg": pick(sample, "soilMoisture7dAvg"),
        "soilTemperature7dAvg": pick(sample, "soilTemperature7dAvg"),
    }

    wind_u = feature_map["windU"]
    wind_v = feature_map["windV"]
    # Keep derived features identical to the Node pipeline so model comparisons
    # are about algorithms, not accidental feature drift.
    feature_map["windSpeed"] = math.sqrt((wind_u**2) + (wind_v**2)) if wind_u is not None and wind_v is not None else None

    date_value = parse_date(sample.get("date"))
    angle = (2 * math.pi * day_of_year(date_value)) / 365.25
    feature_map["dayOfYearSin"] = math.sin(angle)
    feature_map["dayOfYearCos"] = math.cos(angle)

    return feature_map


def load_records(dataset_path: Path, allow_partial: bool) -> tuple[pd.DataFrame, dict[str, Any]]:
    """Load dataset JSON and convert samples into a typed feature DataFrame."""
    dataset = json.loads(dataset_path.read_text(encoding="utf-8"))
    status = dataset.get("status")
    if not allow_partial and status != "complete":
        raise SystemExit(
            f'Dataset status is {status!r}. Re-run the Node generator until status is "complete", '
            "or pass --allow-partial for an interim experiment."
        )

    rows: list[dict[str, Any]] = []
    for index, sample in enumerate(dataset["samples"]):
        date_value = parse_date(sample.get("date"))
        features = build_feature_map(sample)
        rows.append(
            {
                "row_id": index,
                "timestamp": date_value.timestamp(),
                "date": date_value.isoformat(),
                "target": int(sample["label"]),
                **features,
            }
        )

    return pd.DataFrame(rows), dataset


def region_bucket(row: pd.Series, geo_cell_degrees: float) -> str:
    """Map coordinates to coarse geo buckets for held-out-region testing."""
    return f"{math.floor(row['lat'] / geo_cell_degrees)}:{math.floor(row['long'] / geo_cell_degrees)}"


def split_time_and_geography(records: pd.DataFrame, args: argparse.Namespace) -> Split:
    """Split into train/validation/test by time plus held-out geographic cells."""
    # Test data is both later in time and from held-out coarse regions. This is
    # harder than a random split and better matches the real question: does the
    # model generalize to future conditions and nearby-but-unseen places?
    sorted_records = records.sort_values("timestamp").reset_index(drop=True)
    if len(sorted_records) < 3:
        raise SystemExit("Need at least 3 samples to create train/validation/test splits.")

    test_candidate_count = max(1, int(len(sorted_records) * args.test_time_ratio))
    test_candidates = sorted_records.tail(test_candidate_count).copy()
    test_candidates["region_bucket"] = test_candidates.apply(region_bucket, axis=1, geo_cell_degrees=args.geo_cell_degrees)

    region_counts = Counter(test_candidates["region_bucket"])
    sorted_regions = [
        region
        for region, _count in sorted(region_counts.items(), key=lambda item: (-item[1], item[0]))
    ]
    held_out_count = max(1, math.ceil(len(sorted_regions) * args.test_region_ratio))
    held_out_regions = sorted_regions[:held_out_count]

    test = test_candidates[test_candidates["region_bucket"].isin(held_out_regions)].copy()
    if test.empty:
        test = test_candidates.copy()

    test_ids = set(test["row_id"])
    remainder = sorted_records[~sorted_records["row_id"].isin(test_ids)].copy()
    if len(remainder) < 2:
        raise SystemExit("Not enough non-test samples to create training and validation splits.")

    validation_count = max(1, min(len(remainder) - 1, int(len(remainder) * args.validation_time_ratio)))
    training = remainder.iloc[: len(remainder) - validation_count].copy()
    validation = remainder.iloc[len(remainder) - validation_count :].copy()

    return Split(training=training, validation=validation, test=test, held_out_regions=held_out_regions)


def impute_and_normalize(split: Split) -> tuple[Split, dict[str, float], dict[str, dict[str, float]]]:
    """Fit imputation + normalization on train, then apply to all splits."""
    # All preprocessing parameters are learned from training only. Validation
    # and test are transformed with those fixed parameters to avoid data leakage.
    imputation_means: dict[str, float] = {}
    normalization: dict[str, dict[str, float]] = {}

    for feature_name in FEATURE_NAMES:
        values = pd.to_numeric(split.training[feature_name], errors="coerce")
        mean_value = float(values.mean()) if not values.dropna().empty else 0.0
        imputation_means[feature_name] = mean_value

        for frame in (split.training, split.validation, split.test):
            frame[feature_name] = pd.to_numeric(frame[feature_name], errors="coerce").fillna(mean_value)

        train_values = split.training[feature_name].to_numpy(dtype=float)
        train_mean = float(train_values.mean())
        train_std = float(train_values.std())
        if train_std == 0.0 or math.isnan(train_std):
            train_std = 1.0
        normalization[feature_name] = {"mean": train_mean, "std": train_std}

        for frame in (split.training, split.validation, split.test):
            frame[feature_name] = (frame[feature_name] - train_mean) / train_std

    return split, imputation_means, normalization


def matrix(frame: pd.DataFrame) -> np.ndarray:
    """Extract feature matrix in canonical feature order."""
    return frame[FEATURE_NAMES].to_numpy(dtype=float)


def expanded_matrix(x_values: np.ndarray) -> tuple[np.ndarray, list[str]]:
    """Build manual nonlinear expansion (squares + selected interactions)."""
    # The expanded logistic model stays interpretable and serializable while
    # giving it limited nonlinear capacity for common wildfire interactions.
    parts = [x_values]
    names = [f"z:{name}" for name in FEATURE_NAMES]

    parts.append(x_values**2)
    names.extend([f"z:{name}^2" for name in FEATURE_NAMES])

    feature_index = {name: index for index, name in enumerate(FEATURE_NAMES)}
    interaction_columns = []
    for left, right in INTERACTION_PAIRS:
        interaction_columns.append(x_values[:, feature_index[left]] * x_values[:, feature_index[right]])
        names.append(f"z:{left}*z:{right}")

    if interaction_columns:
        parts.append(np.column_stack(interaction_columns))

    return np.column_stack(parts), names


def transform(x_values: np.ndarray, mode: str) -> tuple[np.ndarray, list[str]]:
    """Apply the requested feature transformation mode."""
    if mode == "linear":
        return x_values, [f"z:{name}" for name in FEATURE_NAMES]
    if mode == "expanded":
        return expanded_matrix(x_values)
    raise ValueError(f"Unsupported model mode: {mode}")


def sigmoid(logits: np.ndarray) -> np.ndarray:
    """Numerically stable sigmoid for vector logits."""
    return 1.0 / (1.0 + np.exp(-np.clip(logits, -40, 40)))


def train_logistic(x_values: np.ndarray, y_values: np.ndarray, epochs: int, learning_rate: float, l2_penalty: float) -> tuple[np.ndarray, float]:
    """Train logistic regression with batch gradient descent + L2 penalty."""
    # This mirrors the simple Node baseline so Python can compare "same model,
    # different implementation" before trying sklearn's stronger estimators.
    weights = np.zeros(x_values.shape[1], dtype=float)
    bias = 0.0
    sample_count = len(y_values)

    for _ in range(epochs):
        logits = x_values @ weights + bias
        probabilities = sigmoid(logits)
        error = probabilities - y_values
        grad_weights = (x_values.T @ error) / sample_count + (l2_penalty * weights)
        grad_bias = float(error.mean())
        weights -= learning_rate * grad_weights
        bias -= learning_rate * grad_bias

    return weights, bias


def auc_score(y_values: np.ndarray, probabilities: np.ndarray) -> float | None:
    """Compute ROC AUC with tie-aware rank formulation."""
    positives = int(y_values.sum())
    negatives = len(y_values) - positives
    if positives == 0 or negatives == 0:
        return None

    order = np.argsort(probabilities)
    sorted_scores = probabilities[order]
    ranks = np.empty(len(probabilities), dtype=float)
    rank = 1
    index = 0
    while index < len(probabilities):
        end = index + 1
        while end < len(probabilities) and sorted_scores[end] == sorted_scores[index]:
            end += 1
        average_rank = (rank + (rank + end - index - 1)) / 2
        ranks[order[index:end]] = average_rank
        rank += end - index
        index = end

    positive_rank_sum = float(ranks[y_values == 1].sum())
    return (positive_rank_sum - (positives * (positives + 1) / 2)) / (positives * negatives)


def safe_sklearn_auc(y_values: np.ndarray, probabilities: np.ndarray) -> float | None:
    """Delegate AUC to sklearn when both classes are present."""
    if len(np.unique(y_values)) < 2:
        return None
    return float(roc_auc_score(y_values, probabilities))


def log_loss(y_values: np.ndarray, probabilities: np.ndarray) -> float:
    """Compute mean cross-entropy."""
    clipped = np.clip(probabilities, 1e-9, 1 - 1e-9)
    return float(-(y_values * np.log(clipped) + (1 - y_values) * np.log(1 - clipped)).mean())


def brier_score(y_values: np.ndarray, probabilities: np.ndarray) -> float:
    """Compute mean squared probability error."""
    return float(np.mean((probabilities - y_values) ** 2))


def confusion_metrics(y_values: np.ndarray, probabilities: np.ndarray, threshold: float = 0.5) -> dict[str, float | int]:
    """Compute thresholded confusion-matrix metrics."""
    predictions = probabilities >= threshold
    labels = y_values == 1
    true_positive = int(np.logical_and(predictions, labels).sum())
    true_negative = int(np.logical_and(~predictions, ~labels).sum())
    false_positive = int(np.logical_and(predictions, ~labels).sum())
    false_negative = int(np.logical_and(~predictions, labels).sum())
    accuracy = (true_positive + true_negative) / len(y_values) if len(y_values) else 0.0
    precision = true_positive / (true_positive + false_positive) if true_positive + false_positive else 0.0
    recall = true_positive / (true_positive + false_negative) if true_positive + false_negative else 0.0
    return {
        "accuracy": float(accuracy),
        "precision": float(precision),
        "recall": float(recall),
        "truePositive": true_positive,
        "trueNegative": true_negative,
        "falsePositive": false_positive,
        "falseNegative": false_negative,
    }


def fit_platt(logits: np.ndarray, y_values: np.ndarray) -> dict[str, Any]:
    """Fit Platt scaling on validation logits (or identity fallback)."""
    if len(np.unique(y_values)) < 2:
        return {"type": "identity", "status": "validation_split_has_one_class", "scale": 1.0, "offset": 0.0}

    scale = 1.0
    offset = 0.0
    learning_rate = 0.05
    for _ in range(1200):
        probabilities = sigmoid((scale * logits) + offset)
        error = probabilities - y_values
        scale -= learning_rate * float(np.mean(error * logits))
        offset -= learning_rate * float(error.mean())

    return {"type": "platt", "status": "fit_on_validation", "scale": scale, "offset": offset}


def apply_calibration(logits: np.ndarray, calibration: dict[str, Any] | None) -> np.ndarray:
    """Apply learned calibration parameters to logits."""
    if not calibration or calibration.get("type") == "identity":
        return sigmoid(logits)
    return sigmoid((float(calibration["scale"]) * logits) + float(calibration["offset"]))


def summarize(y_values: np.ndarray, probabilities: np.ndarray) -> dict[str, Any]:
    """Bundle metrics for one split/probability set."""
    return {
        **confusion_metrics(y_values, probabilities),
        "auc": auc_score(y_values, probabilities),
        "logLoss": log_loss(y_values, probabilities),
        "brierScore": brier_score(y_values, probabilities),
    }


def fit_candidate(mode: str, split: Split, args: argparse.Namespace) -> FittedModel:
    """Fit a NumPy logistic candidate and evaluate raw/calibrated metrics."""
    # Raw probabilities measure the model directly. Calibrated probabilities
    # apply a validation-fitted sigmoid so reported risk is better behaved.
    x_train, derived_names = transform(matrix(split.training), mode)
    x_validation, _ = transform(matrix(split.validation), mode)
    x_test, _ = transform(matrix(split.test), mode)
    y_train = split.training["target"].to_numpy(dtype=float)
    y_validation = split.validation["target"].to_numpy(dtype=float)
    y_test = split.test["target"].to_numpy(dtype=float)

    weights, bias = train_logistic(
        x_train,
        y_train,
        epochs=args.epochs,
        learning_rate=args.learning_rate,
        l2_penalty=args.l2_penalty,
    )

    validation_logits = x_validation @ weights + bias
    test_logits = x_test @ weights + bias
    calibration = fit_platt(validation_logits, y_validation)

    validation_raw = summarize(y_validation, sigmoid(validation_logits))
    validation_calibrated = summarize(y_validation, apply_calibration(validation_logits, calibration))
    test_raw = summarize(y_test, sigmoid(test_logits))
    test_calibrated = summarize(y_test, apply_calibration(test_logits, calibration))

    return FittedModel(
        mode=mode,
        feature_names=derived_names,
        weights=weights,
        bias=bias,
        calibration=calibration,
        validation={"raw": validation_raw, "calibrated": validation_calibrated},
        test={"raw": test_raw, "calibrated": test_calibrated},
    )


def summarize_probabilities(y_values: np.ndarray, probabilities: np.ndarray, use_sklearn_auc: bool = False) -> dict[str, Any]:
    """Metric helper for sklearn estimator probabilities."""
    return {
        **confusion_metrics(y_values, probabilities),
        "auc": safe_sklearn_auc(y_values, probabilities) if use_sklearn_auc else auc_score(y_values, probabilities),
        "logLoss": log_loss(y_values, probabilities),
        "brierScore": brier_score(y_values, probabilities),
    }


def fit_sklearn_candidate(mode: str, split: Split, args: argparse.Namespace) -> FittedModel:
    """Fit and evaluate one sklearn candidate model configuration."""
    # sklearn models are used only in this comparison artifact. The production
    # Node path remains available and simpler to inspect/deploy.
    if not SKLEARN_AVAILABLE:
        raise SystemExit("scikit-learn is not installed. Run `poetry add scikit-learn joblib` inside ground_station/ai.")

    x_train = matrix(split.training)
    x_validation = matrix(split.validation)
    x_test = matrix(split.test)
    y_train = split.training["target"].to_numpy(dtype=int)
    y_validation = split.validation["target"].to_numpy(dtype=int)
    y_test = split.test["target"].to_numpy(dtype=int)

    if mode == "sklearn-logistic":
        estimator = make_pipeline(
            StandardScaler(),
            PolynomialFeatures(degree=2, interaction_only=True, include_bias=False),
            LogisticRegression(max_iter=3000, C=1.0, class_weight="balanced"),
        )
    elif mode == "random-forest":
        estimator = RandomForestClassifier(
            n_estimators=250,
            max_depth=10,
            min_samples_leaf=8,
            class_weight="balanced_subsample",
            random_state=42,
            n_jobs=-1,
        )
    elif mode == "extra-trees":
        estimator = ExtraTreesClassifier(
            n_estimators=300,
            max_depth=12,
            min_samples_leaf=6,
            class_weight="balanced",
            random_state=42,
            n_jobs=-1,
        )
    elif mode == "hist-gradient-boosting":
        estimator = HistGradientBoostingClassifier(
            max_iter=220,
            learning_rate=0.05,
            max_leaf_nodes=31,
            l2_regularization=0.01,
            random_state=42,
        )
    else:
        raise ValueError(f"Unsupported scikit-learn model mode: {mode}")

    raw_estimator = clone(estimator)
    raw_estimator.fit(x_train, y_train)
    validation_raw_probabilities = raw_estimator.predict_proba(x_validation)[:, 1]
    test_raw_probabilities = raw_estimator.predict_proba(x_test)[:, 1]

    validation_raw_metrics = summarize_probabilities(y_validation, validation_raw_probabilities, use_sklearn_auc=True)
    test_raw_metrics = summarize_probabilities(y_test, test_raw_probabilities, use_sklearn_auc=True)

    tree_mode = mode in {"random-forest", "extra-trees", "hist-gradient-boosting"}
    calibration = {"type": "estimator_probability", "status": "from_sklearn_predict_proba"}
    calibrated_estimator_name = raw_estimator.__class__.__name__
    validation_calibrated_metrics = validation_raw_metrics
    test_calibrated_metrics = test_raw_metrics

    if tree_mode:
        # Tree models can produce poorly calibrated probabilities. Use sklearn's
        # cross-validated calibrator when each class has enough samples.
        class_counts = np.bincount(y_train)
        nonzero_class_counts = class_counts[class_counts > 0]
        max_folds = int(nonzero_class_counts.min()) if len(nonzero_class_counts) else 0
        calibration_cv = max(0, min(args.calibration_cv, max_folds))
        if calibration_cv >= 2:
            calibrated_estimator = CalibratedClassifierCV(
                estimator=clone(estimator),
                method=args.calibration_method,
                cv=calibration_cv,
            )
            calibrated_estimator.fit(x_train, y_train)
            validation_calibrated_probabilities = calibrated_estimator.predict_proba(x_validation)[:, 1]
            test_calibrated_probabilities = calibrated_estimator.predict_proba(x_test)[:, 1]
            validation_calibrated_metrics = summarize_probabilities(
                y_validation, validation_calibrated_probabilities, use_sklearn_auc=True
            )
            test_calibrated_metrics = summarize_probabilities(y_test, test_calibrated_probabilities, use_sklearn_auc=True)
            calibration = {
                "type": "sklearn_calibrated_classifier_cv",
                "status": "fit_on_training_cross_validation",
                "method": args.calibration_method,
                "cv": calibration_cv,
            }
            calibrated_estimator_name = calibrated_estimator.__class__.__name__
        else:
            calibration = {
                "type": "estimator_probability",
                "status": "not_enough_training_class_members_for_cv_calibration",
                "requestedCv": args.calibration_cv,
                "availableCv": calibration_cv,
            }

    return FittedModel(
        mode=mode,
        feature_names=FEATURE_NAMES,
        weights=None,
        bias=None,
        calibration=calibration,
        validation={"raw": validation_raw_metrics, "calibrated": validation_calibrated_metrics},
        test={"raw": test_raw_metrics, "calibrated": test_calibrated_metrics},
        sklearn_estimator=calibrated_estimator_name,
    )


def choose_model(candidates: list[FittedModel]) -> FittedModel:
    """Choose best candidate by calibrated validation log loss, then AUC."""
    # Log loss is the primary criterion because this pipeline cares about usable
    # probabilities, not only ranking. AUC is a tie-breaker for ranking quality.
    def key(candidate: FittedModel) -> tuple[float, float]:
        log_loss_value = candidate.validation["calibrated"]["logLoss"]
        auc_value = candidate.validation["calibrated"]["auc"]
        return (float(log_loss_value), -float(auc_value) if auc_value is not None else 0.0)

    return min(candidates, key=key)


def to_jsonable(value: Any) -> Any:
    """Convert NumPy-heavy structures into JSON-serializable Python types."""
    if isinstance(value, np.ndarray):
        return value.tolist()
    if isinstance(value, np.generic):
        return value.item()
    if isinstance(value, dict):
        return {key: to_jsonable(inner) for key, inner in value.items()}
    if isinstance(value, list):
        return [to_jsonable(item) for item in value]
    return value


def format_metric(value: Any) -> str:
    """Format metric for terminal output."""
    return "n/a" if value is None else f"{float(value):.4f}"


def print_metrics(label: str, model: FittedModel) -> None:
    """Print calibrated metric summaries for quick candidate comparison."""
    validation = model.validation["calibrated"]
    test = model.test["calibrated"]
    print(f"{label}: {model.mode}")
    print(
        "  validation calibrated AUC/log loss/Brier: "
        f"{format_metric(validation['auc'])} / {format_metric(validation['logLoss'])} / {format_metric(validation['brierScore'])}"
    )
    print(
        "  test calibrated AUC/log loss/Brier:       "
        f"{format_metric(test['auc'])} / {format_metric(test['logLoss'])} / {format_metric(test['brierScore'])}"
    )


def main() -> None:
    """Train selected candidates, pick the best, and write model artifact."""
    args = parse_args()
    dataset_path = Path(args.input).resolve()
    output_path = Path(args.output).resolve()

    records, dataset = load_records(dataset_path, args.allow_partial)
    split = split_time_and_geography(records, args)
    split, imputation_means, normalization = impute_and_normalize(split)

    if args.model == "auto":
        modes = ["linear", "expanded"]
        if SKLEARN_AVAILABLE:
            modes.extend(["sklearn-logistic", "random-forest", "extra-trees", "hist-gradient-boosting"])
    else:
        modes = [args.model]

    candidates = []
    for mode in modes:
        if mode in {"linear", "expanded"}:
            candidates.append(fit_candidate(mode, split, args))
        else:
            candidates.append(fit_sklearn_candidate(mode, split, args))
    selected = choose_model(candidates)

    output_path.parent.mkdir(parents=True, exist_ok=True)
    artifact = {
        # The output artifact is intentionally descriptive rather than a direct
        # runtime pickle/joblib. It records what won, how it was evaluated, and
        # enough preprocessing/model data to audit the comparison.
        "modelType": "python_wildfire_binary_fire_classifier",
        "description": "Python wildfire model trained from the generated Node true-classifier dataset. The existing Node model remains the baseline.",
        "inputDataset": str(dataset_path),
        "datasetStatus": dataset.get("status"),
        "sampleCount": int(len(records)),
        "selectedMode": selected.mode,
        "candidateSelection": "lowest calibrated validation log loss, with AUC as tie-breaker",
        "trainingRows": int(len(split.training)),
        "validationRows": int(len(split.validation)),
        "testRows": int(len(split.test)),
        "heldOutRegions": split.held_out_regions,
        "baseFeatures": FEATURE_NAMES,
        "derivedFeatures": selected.feature_names,
        "imputationMeans": imputation_means,
        "normalization": normalization,
        "weights": selected.weights,
        "bias": selected.bias,
        "calibration": selected.calibration,
        "sklearnAvailable": SKLEARN_AVAILABLE,
        "sklearnEstimator": selected.sklearn_estimator,
        "metrics": {
            candidate.mode: {
                "validation": candidate.validation,
                "test": candidate.test,
            }
            for candidate in candidates
        },
        "nodeBaselineCommand": "node tools/wildfire-risk/train_true_classifier.js",
    }
    output_path.write_text(json.dumps(to_jsonable(artifact), indent=2) + "\n", encoding="utf-8")

    for candidate in candidates:
        print_metrics("Candidate", candidate)
    print(f"Selected model: {selected.mode}")
    print(f"Saved Python wildfire model to {output_path}")


if __name__ == "__main__":
    main()
