"use strict";

const path = require("path");
const {
  applyImputation,
  areaUnderCurve,
  computeImputationStats,
  computeNormalizationStats,
  confusionMetrics,
  loadJson,
  logLoss,
  normalizeVector,
  predictProbability,
  trainLogisticRegression,
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
    }
  }

  return args;
}

function formatMetric(value) {
  return value.toFixed(4);
}

function splitTemporal(records, ratio = 0.8) {
  const sorted = [...records].sort((left, right) => left.timestamp - right.timestamp);
  const splitIndex = Math.max(1, Math.min(sorted.length - 1, Math.floor(sorted.length * ratio)));
  return {
    training: sorted.slice(0, splitIndex),
    validation: sorted.slice(splitIndex),
  };
}

function main() {
  const args = parseArguments(process.argv.slice(2));
  const dataset = loadJson(args.input);
  const records = dataset.samples.map((sample) => {
    const timestamp = new Date(sample.date);
    return {
      timestamp: timestamp.getTime(),
      target: sample.label,
      features: buildTrueClassifierFeatureMap(sample, timestamp),
    };
  });

  const { training, validation } = splitTemporal(records, 0.8);
  const imputationMeans = computeImputationStats(training, TRUE_FEATURE_NAMES);
  applyImputation(training, imputationMeans, TRUE_FEATURE_NAMES);
  applyImputation(validation, imputationMeans, TRUE_FEATURE_NAMES);

  const normalizationStats = computeNormalizationStats(training, TRUE_FEATURE_NAMES);
  training.forEach((record) => {
    record.vector = normalizeVector(record.features, normalizationStats, TRUE_FEATURE_NAMES);
  });
  validation.forEach((record) => {
    record.vector = normalizeVector(record.features, normalizationStats, TRUE_FEATURE_NAMES);
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
    modelType: "logistic_regression_binary_fire_classifier",
    targetDescription: "estimated probability that the sampled coordinate/time belongs to a wildfire-positive event rather than a sampled non-fire background point",
    limitation: "This is a true binary classifier, but the negative class is generated from sampled background coordinates and historical weather, not hand-labeled field truth.",
    trainedAt: new Date().toISOString(),
    trainingData: {
      inputDataset: path.resolve(args.input),
      sampleCount: dataset.samples.length,
      trainingCount: training.length,
      validationCount: validation.length,
      validationStartUtc: new Date(validation[0].timestamp).toISOString(),
      validationEndUtc: new Date(validation[validation.length - 1].timestamp).toISOString(),
      generationParameters: dataset.generationParameters,
    },
    features: TRUE_FEATURE_NAMES,
    imputationMeans,
    normalization: normalizationStats,
    weights: model.weights,
    bias: model.bias,
    metrics,
  };

  require("./common").saveJson(args.output, modelDocument);

  console.log(`Saved model to ${path.resolve(args.output)}`);
  console.log(`Rows: train=${training.length} validation=${validation.length}`);
  console.log(`Validation accuracy: ${formatMetric(metrics.accuracy)}`);
  console.log(`Validation precision: ${formatMetric(metrics.precision)}`);
  console.log(`Validation recall: ${formatMetric(metrics.recall)}`);
  console.log(`Validation AUC: ${formatMetric(metrics.auc)}`);
  console.log(`Validation log loss: ${formatMetric(metrics.logLoss)}`);
}

main();
