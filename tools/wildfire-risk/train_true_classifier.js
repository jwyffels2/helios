"use strict";

// Trains the true wildfire classifier from a generated labeled dataset.
// This script handles the geo/time split, normalization, calibration, metric
// reporting, and writes the model artifact used by live and batch inference.

const path = require("path");
const {
  applyImputation,
  areaUnderCurve,
  brierScore,
  calibrateLogit,
  computeImputationStats,
  computeNormalizationStats,
  fitPlattScaling,
  confusionMetrics,
  loadJson,
  logLoss,
  normalizeVector,
  predictLogit,
  trainLogisticRegression,
  saveJson,
} = require("./common");
const {
  TRUE_FEATURE_NAMES,
  buildTrueClassifierFeatureMap,
} = require("./true_classifier_common");

function parseArguments(argv) {
  const args = {
    input: path.join(__dirname, "output", "true_classifier_dataset.json"),
    output: path.join(__dirname, "output", "true_classifier_model.json"),
    epochs: 800,
    learningRate: 0.05,
    l2Penalty: 0.001,
    testTimeRatio: 0.2,
    testRegionRatio: 0.25,
    validationTimeRatio: 0.2,
    geoCellDegrees: 2,
    allowPartial: false,
  };

  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];
    if (token === "--input") {
      args.input = argv[index + 1];
      index += 1;
    } else if (token === "--output") {
      args.output = argv[index + 1];
      index += 1;
    } else if (token === "--epochs") {
      args.epochs = Number(argv[index + 1]);
      index += 1;
    } else if (token === "--learning-rate") {
      args.learningRate = Number(argv[index + 1]);
      index += 1;
    } else if (token === "--l2-penalty") {
      args.l2Penalty = Number(argv[index + 1]);
      index += 1;
    } else if (token === "--test-time-ratio") {
      args.testTimeRatio = Number(argv[index + 1]);
      index += 1;
    } else if (token === "--test-region-ratio") {
      args.testRegionRatio = Number(argv[index + 1]);
      index += 1;
    } else if (token === "--validation-time-ratio") {
      args.validationTimeRatio = Number(argv[index + 1]);
      index += 1;
    } else if (token === "--geo-cell-degrees") {
      args.geoCellDegrees = Number(argv[index + 1]);
      index += 1;
    } else if (token === "--allow-partial") {
      args.allowPartial = true;
    }
  }

  return args;
}

function formatMetric(value) {
  return value.toFixed(4);
}

function regionBucket(record, geoCellDegrees) {
  const latBucket = Math.floor(record.features.lat / geoCellDegrees);
  const longBucket = Math.floor(record.features.long / geoCellDegrees);
  return `${latBucket}:${longBucket}`;
}

function splitTimeAndGeography(records, options) {
  const sorted = [...records].sort((left, right) => left.timestamp - right.timestamp);
  if (sorted.length < 3) {
    throw new Error("Need at least 3 samples to create train/validation/test splits.");
  }

  const testCandidateCount = Math.max(1, Math.floor(sorted.length * options.testTimeRatio));
  const testCandidates = sorted.slice(sorted.length - testCandidateCount);
  const remainderBeforeValidation = sorted.slice(0, sorted.length - testCandidateCount);

  const regionCounts = new Map();
  for (const record of testCandidates) {
    const bucket = regionBucket(record, options.geoCellDegrees);
    regionCounts.set(bucket, (regionCounts.get(bucket) ?? 0) + 1);
  }

  const sortedRegions = [...regionCounts.entries()]
    .sort((left, right) => {
      if (right[1] !== left[1]) {
        return right[1] - left[1];
      }
      return left[0].localeCompare(right[0]);
    })
    .map(([bucket]) => bucket);

  const heldOutRegionCount = Math.max(1, Math.ceil(sortedRegions.length * options.testRegionRatio));
  const heldOutRegions = new Set(sortedRegions.slice(0, heldOutRegionCount));

  let test = testCandidates.filter((record) => heldOutRegions.has(regionBucket(record, options.geoCellDegrees)));
  if (test.length === 0) {
    test = [...testCandidates];
  }

  const remainder = sorted.filter((record) => !test.includes(record));
  if (remainder.length < 2) {
    throw new Error("Not enough remaining samples after test split to create training and validation sets.");
  }

  const validationCount = Math.max(1, Math.min(remainder.length - 1, Math.floor(remainder.length * options.validationTimeRatio)));
  const splitIndex = remainder.length - validationCount;

  return {
    training: remainder.slice(0, splitIndex),
    validation: remainder.slice(splitIndex),
    test,
    splitSummary: {
      testCandidateCount,
      heldOutRegions: [...heldOutRegions],
      geoCellDegrees: options.geoCellDegrees,
    },
  };
}

function scoreRecords(records, model) {
  return records.map((record) => ({
    target: record.target,
    logit: predictLogit(record.vector, model),
  }));
}

function applyCalibration(scoredRecords, calibration) {
  return scoredRecords.map((record) => ({
    target: record.target,
    probability: calibrateLogit(record.logit, calibration),
  }));
}

function logitsToRawProbabilities(scoredRecords) {
  return scoredRecords.map((record) => ({
    target: record.target,
    probability: calibrateLogit(record.logit, null),
  }));
}

function summarizeMetrics(scoredRecords) {
  return {
    ...confusionMetrics(scoredRecords, 0.5),
    auc: areaUnderCurve(scoredRecords),
    logLoss: logLoss(scoredRecords),
    brierScore: brierScore(scoredRecords),
  };
}

function main() {
  const args = parseArguments(process.argv.slice(2));
  const dataset = loadJson(args.input);
  if (!args.allowPartial && dataset.status !== "complete") {
    throw new Error(
      `Dataset status is ${JSON.stringify(dataset.status ?? null)}. Refusing to train until the dataset is complete. Re-run the generator or pass --allow-partial to override.`
    );
  }
  const records = dataset.samples.map((sample) => {
    const timestamp = new Date(sample.date);
    return {
      timestamp: timestamp.getTime(),
      target: sample.label,
      features: buildTrueClassifierFeatureMap(sample, timestamp),
    };
  });

  const {
    training,
    validation,
    test,
    splitSummary,
  } = splitTimeAndGeography(records, {
    testTimeRatio: args.testTimeRatio,
    testRegionRatio: args.testRegionRatio,
    validationTimeRatio: args.validationTimeRatio,
    geoCellDegrees: args.geoCellDegrees,
  });
  const imputationMeans = computeImputationStats(training, TRUE_FEATURE_NAMES);
  applyImputation(training, imputationMeans, TRUE_FEATURE_NAMES);
  applyImputation(validation, imputationMeans, TRUE_FEATURE_NAMES);
  applyImputation(test, imputationMeans, TRUE_FEATURE_NAMES);

  const normalizationStats = computeNormalizationStats(training, TRUE_FEATURE_NAMES);
  training.forEach((record) => {
    record.vector = normalizeVector(record.features, normalizationStats, TRUE_FEATURE_NAMES);
  });
  validation.forEach((record) => {
    record.vector = normalizeVector(record.features, normalizationStats, TRUE_FEATURE_NAMES);
  });
  test.forEach((record) => {
    record.vector = normalizeVector(record.features, normalizationStats, TRUE_FEATURE_NAMES);
  });

  const model = trainLogisticRegression(training, {
    epochs: args.epochs,
    learningRate: args.learningRate,
    l2Penalty: args.l2Penalty,
  });

  const validationLogits = scoreRecords(validation, model);
  const testLogits = scoreRecords(test, model);
  const calibration = fitPlattScaling(validationLogits);
  const validationRawMetrics = summarizeMetrics(logitsToRawProbabilities(validationLogits));
  const validationCalibratedMetrics = summarizeMetrics(applyCalibration(validationLogits, calibration));
  const testRawMetrics = summarizeMetrics(logitsToRawProbabilities(testLogits));
  const testCalibratedMetrics = summarizeMetrics(applyCalibration(testLogits, calibration));

  const modelDocument = {
    modelType: "logistic_regression_binary_fire_classifier",
    targetDescription: "calibrated estimate that the sampled coordinate/time belongs to a wildfire-positive event rather than a sampled non-fire background point",
    limitation: "This is a true binary classifier, but the negative class is generated from sampled background coordinates and historical weather, not hand-labeled field truth.",
    trainedAt: new Date().toISOString(),
    trainingData: {
      inputDataset: path.resolve(args.input),
      sampleCount: dataset.samples.length,
      trainingCount: training.length,
      validationCount: validation.length,
      testCount: test.length,
      validationStartUtc: new Date(validation[0].timestamp).toISOString(),
      validationEndUtc: new Date(validation[validation.length - 1].timestamp).toISOString(),
      testStartUtc: new Date(test[0].timestamp).toISOString(),
      testEndUtc: new Date(test[test.length - 1].timestamp).toISOString(),
      generationParameters: dataset.generationParameters,
      splitStrategy: {
        type: "time_plus_geography",
        ...splitSummary,
        testTimeRatio: args.testTimeRatio,
        testRegionRatio: args.testRegionRatio,
        validationTimeRatio: args.validationTimeRatio,
      },
    },
    features: TRUE_FEATURE_NAMES,
    imputationMeans,
    normalization: normalizationStats,
    weights: model.weights,
    bias: model.bias,
    calibration,
    metrics: {
      validation: {
        raw: validationRawMetrics,
        calibrated: validationCalibratedMetrics,
      },
      test: {
        raw: testRawMetrics,
        calibrated: testCalibratedMetrics,
      },
    },
  };

  saveJson(args.output, modelDocument);

  console.log(`Saved model to ${path.resolve(args.output)}`);
  console.log(`Rows: train=${training.length} validation=${validation.length} test=${test.length}`);
  console.log(`Calibration: ${calibration.type} (${calibration.status})`);
  console.log(`Validation raw AUC: ${formatMetric(validationRawMetrics.auc)}`);
  console.log(`Validation raw log loss: ${formatMetric(validationRawMetrics.logLoss)}`);
  console.log(`Validation raw Brier: ${formatMetric(validationRawMetrics.brierScore)}`);
  console.log(`Validation calibrated AUC: ${formatMetric(validationCalibratedMetrics.auc)}`);
  console.log(`Validation calibrated log loss: ${formatMetric(validationCalibratedMetrics.logLoss)}`);
  console.log(`Validation calibrated Brier: ${formatMetric(validationCalibratedMetrics.brierScore)}`);
  console.log(`Test raw AUC: ${formatMetric(testRawMetrics.auc)}`);
  console.log(`Test raw log loss: ${formatMetric(testRawMetrics.logLoss)}`);
  console.log(`Test raw Brier: ${formatMetric(testRawMetrics.brierScore)}`);
  console.log(`Test calibrated AUC: ${formatMetric(testCalibratedMetrics.auc)}`);
  console.log(`Test calibrated log loss: ${formatMetric(testCalibratedMetrics.logLoss)}`);
  console.log(`Test calibrated Brier: ${formatMetric(testCalibratedMetrics.brierScore)}`);
}

main();
