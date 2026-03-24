"use strict";

// Verifies that the true wildfire classifier can score a fixed fixture input.
// This is a lightweight regression check for the inference path: it confirms
// the model loads, probabilities stay in range, and the fixture does not
// require unexpected imputations.

const path = require("path");
const {
  loadJson,
  saveJson,
} = require("./common");
const {
  scoreTrueClassifierInput,
} = require("./true_classifier_runtime");

function parseArguments(argv) {
  const args = {
    model: path.join(__dirname, "output", "true_classifier_model.json"),
    fixture: path.join(__dirname, "true_classifier_fixture_input.json"),
    output: null,
  };

  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];
    if (token === "--model") {
      args.model = argv[index + 1];
      index += 1;
    } else if (token === "--fixture") {
      args.fixture = argv[index + 1];
      index += 1;
    } else if (token === "--output") {
      args.output = argv[index + 1];
      index += 1;
    }
  }

  return args;
}

function ensureProbabilityRange(value, label) {
  if (!Number.isFinite(value) || value < 0 || value > 1) {
    throw new Error(`${label} must be a finite probability in [0, 1].`);
  }
}

function main() {
  const args = parseArguments(process.argv.slice(2));
  const model = loadJson(args.model);
  const fixture = loadJson(args.fixture);
  const {
    completedFeatureMap,
    missingFeatures,
    rawProbability,
    calibratedProbability,
  } = scoreTrueClassifierInput(fixture, model, new Date(fixture.date));

  ensureProbabilityRange(rawProbability, "rawProbability");
  ensureProbabilityRange(calibratedProbability, "wildfireProbability");

  const result = {
    model: path.resolve(args.model),
    fixture: path.resolve(args.fixture),
    calibration: model.calibration ?? null,
    rawProbability,
    wildfireProbability: calibratedProbability,
    missingFeaturesImputed: missingFeatures,
    featuresUsed: completedFeatureMap,
  };

  if (args.output) {
    saveJson(args.output, result);
  }

  console.log(JSON.stringify(result, null, 2));

  if (missingFeatures.length > 0) {
    throw new Error(`Fixture should be complete, but ${missingFeatures.length} features were imputed.`);
  }
}

try {
  main();
} catch (error) {
  console.error(error.message);
  process.exitCode = 1;
}
