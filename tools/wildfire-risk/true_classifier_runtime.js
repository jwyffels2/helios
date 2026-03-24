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
  const rawFeatureMap = buildTrueClassifierFeatureMap(inputRecord, fallbackDate);
  const { completedFeatureMap, missingFeatures } = imputeFeatureMap(
    rawFeatureMap,
    model.imputationMeans,
    TRUE_FEATURE_NAMES
  );
  const vector = normalizeVector(completedFeatureMap, model.normalization, TRUE_FEATURE_NAMES);
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
