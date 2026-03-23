"use strict";

const fs = require("fs");
const path = require("path");
const {
  imputeFeatureMap,
  loadJson,
  normalizeVector,
  predictProbability,
  saveJson,
} = require("./common");
const {
  TRUE_FEATURE_NAMES,
  buildTrueClassifierFeatureMap,
} = require("./true_classifier_common");
const {
  fetchOpenMeteoForecast,
  mapForecastPayloadToTrueClassifierInput,
} = require("./weather_api");

function parseArguments(argv) {
  const args = {
    model: path.join(__dirname, "output", "true_classifier_model.json"),
    output: null,
    latitude: null,
    longitude: null,
    date: null,
    sourceFile: null,
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
    }
  }

  if (!Number.isFinite(args.latitude) || !Number.isFinite(args.longitude)) {
    throw new Error("Both --lat and --long are required.");
  }

  return args;
}

async function loadWeatherPayload(args) {
  if (args.sourceFile) {
    const json = fs.readFileSync(path.resolve(args.sourceFile), "utf8");
    return JSON.parse(json);
  }

  return fetchOpenMeteoForecast(args.latitude, args.longitude);
}

async function main() {
  const args = parseArguments(process.argv.slice(2));
  const model = loadJson(args.model);
  const weatherPayload = await loadWeatherPayload(args);
  const apiMappedInput = mapForecastPayloadToTrueClassifierInput(
    weatherPayload,
    args.latitude,
    args.longitude,
    args.date
  );
  const rawFeatureMap = buildTrueClassifierFeatureMap(apiMappedInput, new Date(apiMappedInput.date));
  const { completedFeatureMap, missingFeatures } = imputeFeatureMap(
    rawFeatureMap,
    model.imputationMeans,
    TRUE_FEATURE_NAMES
  );
  const vector = normalizeVector(completedFeatureMap, model.normalization, TRUE_FEATURE_NAMES);
  const probability = predictProbability(vector, model);

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
    apiMappedInput,
    wildfireProbability: probability,
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
