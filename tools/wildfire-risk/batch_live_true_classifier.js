"use strict";

// Scores a CSV of coordinate requests with the true wildfire classifier.
// This is the batch demo path: it loads multiple locations, fetches or replays
// weather data for each row, ranks the results, and writes CSV/JSON outputs for
// presentation or downstream review.

const path = require("path");
const {
  loadCsv,
  loadJson,
  parseNumber,
  saveJson,
  writeCsv,
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
  const args = {
    model: path.join(__dirname, "output", "true_classifier_model.json"),
    input: null,
    outputJson: null,
    outputCsv: null,
    sourceFile: null,
    contextCsv: DEFAULT_CONTEXT_CSV,
  };

  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];

    if (token === "--model") {
      args.model = argv[index + 1];
      index += 1;
    } else if (token === "--input") {
      args.input = argv[index + 1];
      index += 1;
    } else if (token === "--output-json") {
      args.outputJson = argv[index + 1];
      index += 1;
    } else if (token === "--output-csv") {
      args.outputCsv = argv[index + 1];
      index += 1;
    } else if (token === "--source-file") {
      args.sourceFile = argv[index + 1];
      index += 1;
    } else if (token === "--context-csv") {
      args.contextCsv = argv[index + 1];
      index += 1;
    }
  }

  if (!args.input) {
    throw new Error("--input is required.");
  }

  return args;
}

function normalizeBatchRow(row, index) {
  const latitude = parseNumber(row.lat ?? row.latitude);
  const longitude = parseNumber(row.long ?? row.lon ?? row.longitude);

  if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) {
    throw new Error(`Row ${index + 1} is missing a valid lat/long pair.`);
  }

  return {
    id: row.id ?? row.name ?? `row-${index + 1}`,
    lat: latitude,
    long: longitude,
    date: row.date ?? null,
  };
}

async function loadWeatherPayload(args, latitude, longitude) {
  if (args.sourceFile) {
    return loadJson(args.sourceFile);
  }

  return fetchOpenMeteoForecast(latitude, longitude);
}

async function scoreRow(row, args, model, contextIndex) {
  const weatherPayload = await loadWeatherPayload(args, row.lat, row.long);
  const apiMappedInput = mapForecastPayloadToTrueClassifierInput(
    weatherPayload,
    row.lat,
    row.long,
    row.date
  );
  Object.assign(apiMappedInput, lookupNearestContext(contextIndex, apiMappedInput));

  const {
    completedFeatureMap,
    missingFeatures,
    rawProbability,
    calibratedProbability,
  } = scoreTrueClassifierInput(apiMappedInput, model, new Date(apiMappedInput.date));

  return {
    id: row.id,
    lat: row.lat,
    long: row.long,
    date: apiMappedInput.date,
    rawProbability,
    wildfireProbability: calibratedProbability,
    missingFeatureCount: missingFeatures.length,
    missingFeatures,
    featuresUsed: completedFeatureMap,
  };
}

function printSummary(results) {
  const topResults = results.slice(0, 10);
  topResults.forEach((result, index) => {
    console.log(
      `${index + 1}. ${result.id} (${result.lat}, ${result.long}) -> ${result.wildfireProbability.toFixed(4)}`
    );
  });
}

async function main() {
  const args = parseArguments(process.argv.slice(2));
  const model = loadJson(args.model);
  const contextIndex = buildContextIndex(args.contextCsv);
  const rows = loadCsv(args.input).map(normalizeBatchRow);
  const results = [];

  for (const row of rows) {
    results.push(await scoreRow(row, args, model, contextIndex));
  }

  results.sort((left, right) => right.wildfireProbability - left.wildfireProbability);

  const outputDocument = {
    input: path.resolve(args.input),
    model: path.resolve(args.model),
    contextSource: contextIndex.csvPath,
    calibration: model.calibration ?? null,
    source: args.sourceFile
      ? {
          type: "file",
          path: path.resolve(args.sourceFile),
        }
      : {
          type: "open-meteo",
          url: "https://api.open-meteo.com/v1/forecast",
        },
    resultCount: results.length,
    results,
  };

  if (args.outputJson) {
    saveJson(args.outputJson, outputDocument);
  }

  if (args.outputCsv) {
    writeCsv(
      args.outputCsv,
      ["id", "lat", "long", "date", "rawProbability", "wildfireProbability", "missingFeatureCount"],
      results
    );
  }

  printSummary(results);
  if (!args.outputJson && !args.outputCsv) {
    console.log(JSON.stringify(outputDocument, null, 2));
  }
}

main().catch((error) => {
  console.error(error.message);
  process.exitCode = 1;
});
