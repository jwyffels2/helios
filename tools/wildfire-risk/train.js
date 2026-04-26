"use strict";

// Trains the original "proxy risk" baseline model from FIRMS-only detections.
// This model predicts high-confidence detection likelihood, not true wildfire
// occurrence, and is kept for baseline comparison against the true classifier.

const path = require("path");
const {
  FEATURE_NAMES,
  applyImputation,
  areaUnderCurve,
  buildFeatureMap,
  computeImputationStats,
  computeNormalizationStats,
  confidenceToTarget,
  confusionMetrics,
  loadCsv,
  logLoss,
  normalizeVector,
  parseDateValue,
  saveJson,
  splitTemporal,
  trainLogisticRegression,
  predictProbability,
} = require("./common");

function parseArguments(argv) {
  // CLI options intentionally mirror common logistic-regression hyperparameters
  // so model behavior can be tuned from the command line without code edits.
  const args = {
    csv: "c:\\Users\\Leonard\\Desktop\\firms_ee_feature_join.csv",
    output: path.join(__dirname, "output", "model.json"),
    confidenceThreshold: 80,
    epochs: 800,
    learningRate: 0.05,
    l2Penalty: 0.001,
  };

  for (let index = 0; index < argv.length; index += 1) {
    const value = argv[index];
    if (value === "--csv") {
      args.csv = argv[index + 1];
      index += 1;
    } else if (value === "--output") {
      args.output = argv[index + 1];
      index += 1;
    } else if (value === "--confidence-threshold") {
      args.confidenceThreshold = Number(argv[index + 1]);
      index += 1;
    } else if (value === "--epochs") {
      args.epochs = Number(argv[index + 1]);
      index += 1;
    } else if (value === "--learning-rate") {
      args.learningRate = Number(argv[index + 1]);
      index += 1;
    } else if (value === "--l2-penalty") {
      args.l2Penalty = Number(argv[index + 1]);
      index += 1;
    }
  }

  return args;
}

function formatMetric(value) {
  return value.toFixed(4);
}

function main() {
  // Parse and featurize all valid rows.
  const args = parseArguments(process.argv.slice(2));
  const rawRows = loadCsv(args.csv);

  const preparedRows = rawRows
    .map((row) => {
      const timestamp = parseDateValue(row.date);
      if (!timestamp) {
        return null;
      }

      return {
        timestamp: timestamp.getTime(),
        target: confidenceToTarget(row.confidence, args.confidenceThreshold),
        features: buildFeatureMap(row, timestamp),
      };
    })
    .filter(Boolean);

  const { training, validation } = splitTemporal(preparedRows, 0.8);
  // Compute imputation/normalization from training data only to avoid leakage.
  const imputationMeans = computeImputationStats(training);
  applyImputation(training, imputationMeans);
  applyImputation(validation, imputationMeans);

  const normalizationStats = computeNormalizationStats(training);
  training.forEach((record) => {
    record.vector = normalizeVector(record.features, normalizationStats);
  });
  validation.forEach((record) => {
    record.vector = normalizeVector(record.features, normalizationStats);
  });

  const model = trainLogisticRegression(training, {
    epochs: args.epochs,
    learningRate: args.learningRate,
    l2Penalty: args.l2Penalty,
  });

  const scoredValidation = validation.map((record) => ({
    target: record.target,
    probability: predictProbability(record.vector, model),
  }));

  const metrics = {
    ...confusionMetrics(scoredValidation, 0.5),
    auc: areaUnderCurve(scoredValidation),
    logLoss: logLoss(scoredValidation),
  };

  const modelDocument = {
    modelType: "logistic_regression",
    targetDescription: `proxy probability that a FIRMS detection is high confidence (confidence >= ${args.confidenceThreshold})`,
    limitation: "This is a wildfire-risk proxy trained only on fire detections. It is not a calibrated wildfire-occurrence probability model because the dataset does not include explicit non-fire examples.",
    trainedAt: new Date().toISOString(),
    trainingData: {
      csvPath: path.resolve(args.csv),
      rowCount: preparedRows.length,
      trainingCount: training.length,
      validationCount: validation.length,
      validationStartUtc: new Date(validation[0].timestamp).toISOString(),
      validationEndUtc: new Date(validation[validation.length - 1].timestamp).toISOString(),
    },
    features: FEATURE_NAMES,
    imputationMeans,
    normalization: normalizationStats,
    weights: model.weights,
    bias: model.bias,
    metrics,
  };

  saveJson(args.output, modelDocument);

  // Print concise training diagnostics for quick experiment tracking.
  console.log(`Saved model to ${path.resolve(args.output)}`);
  console.log(`Rows: train=${training.length} validation=${validation.length}`);
  console.log(`Validation accuracy: ${formatMetric(metrics.accuracy)}`);
  console.log(`Validation precision: ${formatMetric(metrics.precision)}`);
  console.log(`Validation recall: ${formatMetric(metrics.recall)}`);
  console.log(`Validation AUC: ${formatMetric(metrics.auc)}`);
  console.log(`Validation log loss: ${formatMetric(metrics.logLoss)}`);
}

main();
