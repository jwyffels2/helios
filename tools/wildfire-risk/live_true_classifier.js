"use strict";

// Scores one coordinate/date request with the true wildfire classifier.
// This is the single-point demo/inference entry point: it fetches or replays
// weather data, merges nearest context features, runs the model, and prints the
// calibrated probability plus the completed feature set.

const fs = require("fs");
const path = require("path");
const {
  loadJson,
  saveJson,
} = require("./common");
const {
  fetchOpenMeteoForecast,
  mapForecastPayloadToTrueClassifierInput,
} = require("./weather_api");
const {
  DEFAULT_CONTEXT_CSV,
  buildContextIndex,
  lookupNearestContext,
} = require("./context_lookup");
const {
  scoreTrueClassifierInput,
} = require("./true_classifier_runtime");

function parseArguments(argv) {
  // Parse CLI overrides for one-point scoring.
  const args = {
    model: path.join(__dirname, "output", "true_classifier_model.json"),
    output: null,
    latitude: null,
    longitude: null,
    date: null,
    sourceFile: null,
    contextCsv: DEFAULT_CONTEXT_CSV,
  };

  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];

    if (token === "--model") {
      args.model = argv[index + 1];
      index += 1;
    } else if (token === "--output") {
      args.output = argv[index + 1];
      index += 1;
    } else if (token === "--lat") {
      args.latitude = Number(argv[index + 1]);
      index += 1;
    } else if (token === "--long" || token === "--lon") {
      args.longitude = Number(argv[index + 1]);
      index += 1;
    } else if (token === "--date") {
      args.date = argv[index + 1];
      index += 1;
    } else if (token === "--source-file") {
      args.sourceFile = argv[index + 1];
      index += 1;
    } else if (token === "--context-csv") {
      args.contextCsv = argv[index + 1];
      index += 1;
    }
  }

  if (!Number.isFinite(args.latitude) || !Number.isFinite(args.longitude)) {
    throw new Error("Both --lat and --long are required.");
  }

  return args;
}

async function loadWeatherPayload(args) {
  // Offline replay mode is useful for deterministic demos/tests.
  if (args.sourceFile) {
    const json = fs.readFileSync(path.resolve(args.sourceFile), "utf8");
    return JSON.parse(json);
  }

  return fetchOpenMeteoForecast(args.latitude, args.longitude);
}

async function main() {
  // Single-point true-classifier scoring flow:
  // weather fetch -> context lookup -> feature completion -> probability output.
  const args = parseArguments(process.argv.slice(2));
  const model = loadJson(args.model);
  const weatherPayload = await loadWeatherPayload(args);
  const contextIndex = buildContextIndex(args.contextCsv);
  const apiMappedInput = mapForecastPayloadToTrueClassifierInput(
    weatherPayload,
    args.latitude,
    args.longitude,
    args.date
  );
  Object.assign(apiMappedInput, lookupNearestContext(contextIndex, apiMappedInput));
  const {
    completedFeatureMap,
    missingFeatures,
    rawProbability,
    calibratedProbability,
  } = scoreTrueClassifierInput(apiMappedInput, model, new Date(apiMappedInput.date));

  const result = {
    source: args.sourceFile
      ? {
          type: "file",
          path: path.resolve(args.sourceFile),
        }
      : {
          type: "open-meteo",
          url: "https://api.open-meteo.com/v1/forecast",
        },
    coordinates: {
      lat: args.latitude,
      long: args.longitude,
    },
    contextSource: contextIndex.csvPath,
    apiMappedInput,
    calibration: model.calibration ?? null,
    rawProbability,
    wildfireProbability: calibratedProbability,
    missingFeaturesImputed: missingFeatures,
    featuresUsed: completedFeatureMap,
    targetDescription: model.targetDescription,
    limitation: model.limitation,
  };

  if (args.output) {
    saveJson(args.output, result);
  }

  console.log(JSON.stringify(result, null, 2));
}

main().catch((error) => {
  console.error(error.message);
  process.exitCode = 1;
});
