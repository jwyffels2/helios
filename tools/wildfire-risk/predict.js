"use strict";

// CLI entry point for single-record inference with the baseline proxy model.
// It accepts either a JSON input document, direct CLI feature values, or both
// (CLI wins), then applies the exact same feature pipeline used during training.

const path = require("path");
const {
  FEATURE_NAMES,
  buildFeatureMap,
  imputeFeatureMap,
  loadJson,
  normalizeVector,
  predictProbability,
} = require("./common");

function parseArguments(argv) {
  // Keep argument parsing explicit so users can see which flags map to which
  // model inputs when running this script manually.
  const args = {
    model: path.join(__dirname, "output", "model.json"),
    input: null,
    values: {},
  };

  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];

    if (token === "--model") {
      args.model = argv[index + 1];
      index += 1;
    } else if (token === "--input") {
      args.input = argv[index + 1];
      index += 1;
    } else if (token.startsWith("--")) {
      const key = token.slice(2);
      args.values[key] = argv[index + 1];
      index += 1;
    }
  }

  return args;
}

function inputToRecord(inputDocument, cliValues) {
  // Normalize the combined input into the raw-record schema expected by
  // buildFeatureMap. This keeps training and inference feature names aligned.
  // CLI values override JSON so a saved payload can be reused while tweaking one
  // field from the terminal.
  return {
    lat: cliValues.lat ?? inputDocument.lat,
    long: cliValues.long ?? cliValues.lon ?? inputDocument.long ?? inputDocument.lon,
    Ground_Heat_Flux_surface: cliValues["ground-heat-flux"] ?? inputDocument.groundHeatFlux,
    Plant_Canopy_Surface_Water_surface: cliValues["canopy-water"] ?? inputDocument.canopyWater,
    Temperature_surface: cliValues["temperature-surface"] ?? inputDocument.temperatureSurface,
    Vegetation_Type_surface: cliValues["vegetation-type"] ?? inputDocument.vegetationType,
    Vegetation_surface: cliValues.vegetation ?? inputDocument.vegetation,
    pdsi: cliValues.pdsi ?? inputDocument.pdsi,
    precipitation: cliValues.precipitation ?? inputDocument.precipitation,
    tmax: cliValues.tmax ?? inputDocument.tmax,
    tmin: cliValues.tmin ?? inputDocument.tmin,
    "u-component_of_wind_hybrid": cliValues["wind-u"] ?? inputDocument.windU,
    "v-component_of_wind_hybrid": cliValues["wind-v"] ?? inputDocument.windV,
    date: cliValues.date ?? inputDocument.date ?? new Date().toISOString(),
  };
}

function main() {
  // 1) Load model + input.
  // 2) Build/impute/normalize features.
  // 3) Score with logistic regression and print a human-readable JSON response.
  const args = parseArguments(process.argv.slice(2));
  const model = loadJson(args.model);
  const inputDocument = args.input ? loadJson(args.input) : {};
  const pseudoRecord = inputToRecord(inputDocument, args.values);
  const featureMap = buildFeatureMap(pseudoRecord, new Date(pseudoRecord.date));
  const { completedFeatureMap, missingFeatures } = imputeFeatureMap(featureMap, model.imputationMeans);
  const vector = normalizeVector(completedFeatureMap, model.normalization);
  const probability = predictProbability(vector, model);

  const response = {
    // This baseline reports proxyRiskProbability because it was trained on
    // FIRMS confidence labels, not explicit fire-vs-background examples.
    modelType: model.modelType,
    targetDescription: model.targetDescription,
    proxyRiskProbability: probability,
    missingFeaturesImputed: missingFeatures,
    featuresUsed: completedFeatureMap,
    limitation: model.limitation,
  };

  console.log(JSON.stringify(response, null, 2));
}

main();
