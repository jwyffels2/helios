"use strict";

// Shared runtime scoring helper for the true wildfire classifier.
// Centralizing this logic keeps single-point inference, batch inference, and
// fixture verification consistent on imputation, normalization, raw score, and
// calibrated probability handling.

const {
  calibrateLogit,
  imputeFeatureMap,
  normalizeVector,
  predictLogit,
  predictProbability,
} = require("./common");
const {
  TRUE_FEATURE_NAMES,
  buildTrueClassifierFeatureMap,
} = require("./true_classifier_common");

function scoreTrueClassifierInput(inputRecord, model, fallbackDate) {
  // Shared inference pipeline:
  // 1) construct feature map, 2) impute missing fields, 3) normalize to model
  // space, 4) compute raw score, 5) apply probability calibration.
  const featureNames = Array.isArray(model.features) ? model.features : TRUE_FEATURE_NAMES;
  const rawFeatureMap = buildTrueClassifierFeatureMap(inputRecord, fallbackDate);
  const { completedFeatureMap, missingFeatures } = imputeFeatureMap(
    rawFeatureMap,
    model.imputationMeans,
    featureNames
  );
  const vector = normalizeVector(completedFeatureMap, model.normalization, featureNames);
  // The saved logistic model works in normalized vector space. rawLogit is the
  // linear model score; rawProbability is sigmoid(rawLogit); calibratedProbability
  // applies the validation-fitted calibration stored in the model artifact.
  const rawLogit = predictLogit(vector, model);
  const rawProbability = predictProbability(vector, model);
  const calibratedProbability = calibrateLogit(rawLogit, model.calibration);

  return {
    rawFeatureMap,
    completedFeatureMap,
    missingFeatures,
    vector,
    rawLogit,
    rawProbability,
    calibratedProbability,
  };
}

module.exports = {
  scoreTrueClassifierInput,
};
