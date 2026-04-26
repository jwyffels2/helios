"use strict";

// Baseline live adapter:
// fetches near-real-time weather for one coordinate, maps API fields into the
// baseline model schema, then runs proxy-risk inference.

const fs = require("fs");
const path = require("path");
const {
  buildFeatureMap,
  imputeFeatureMap,
  loadJson,
  normalizeVector,
  predictProbability,
  saveJson,
} = require("./common");
const {
  windComponentsFromSpeedAndDirection,
} = require("./weather_api");

function parseArguments(argv) {
  // Require coordinates because everything else can be inferred or defaulted.
  const args = {
    model: path.join(__dirname, "output", "model.json"),
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

function firstValue(array) {
  // Daily arrays from Open-Meteo are 1-day windows for this script, so the
  // first value is the relevant one.
  return Array.isArray(array) && array.length > 0 ? array[0] : null;
}

function mapWeatherResponseToModelInput(payload, latitude, longitude, dateOverride) {
  // Flatten Open-Meteo payload structure to the model's raw input keys.
  const current = payload.current ?? {};
  const daily = payload.daily ?? {};
  const windSpeed = current.wind_speed_10m;
  const windDirection = current.wind_direction_10m;
  const { windU, windV } = windComponentsFromSpeedAndDirection(windSpeed, windDirection);

  return {
    lat: latitude,
    long: longitude,
    date: dateOverride ?? (current.time ? `${current.time}Z` : null) ?? new Date().toISOString(),
    temperatureSurface: current.temperature_2m ?? null,
    precipitation: current.precipitation ?? null,
    tmax: firstValue(daily.temperature_2m_max),
    tmin: firstValue(daily.temperature_2m_min),
    windU,
    windV,
  };
}

function modelInputToRawRecord(modelInput) {
  // Rename to the same column-style keys used in the training CSV.
  return {
    lat: modelInput.lat,
    long: modelInput.long,
    date: modelInput.date,
    Temperature_surface: modelInput.temperatureSurface,
    precipitation: modelInput.precipitation,
    tmax: modelInput.tmax,
    tmin: modelInput.tmin,
    "u-component_of_wind_hybrid": modelInput.windU,
    "v-component_of_wind_hybrid": modelInput.windV,
  };
}

async function fetchOpenMeteoForecast(latitude, longitude) {
  // This adapter belongs to the older proxy model, so it requests only the
  // smaller set of weather fields that model can consume.
  const url = new URL("https://api.open-meteo.com/v1/forecast");
  url.searchParams.set("latitude", String(latitude));
  url.searchParams.set("longitude", String(longitude));
  url.searchParams.set("timezone", "UTC");
  url.searchParams.set("forecast_days", "1");
  url.searchParams.set("temperature_unit", "celsius");
  url.searchParams.set("precipitation_unit", "mm");
  url.searchParams.set("wind_speed_unit", "ms");
  url.searchParams.set(
    "current",
    "temperature_2m,precipitation,wind_speed_10m,wind_direction_10m"
  );
  url.searchParams.set("daily", "temperature_2m_max,temperature_2m_min");

  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`Open-Meteo request failed with status ${response.status}`);
  }

  return response.json();
}

async function loadWeatherPayload(args) {
  // Supports both online mode (API) and deterministic offline replay.
  if (args.sourceFile) {
    const json = fs.readFileSync(path.resolve(args.sourceFile), "utf8");
    return JSON.parse(json);
  }

  return fetchOpenMeteoForecast(args.latitude, args.longitude);
}

async function main() {
  // End-to-end inference flow for one location.
  const args = parseArguments(process.argv.slice(2));
  const model = loadJson(args.model);
  const weatherPayload = await loadWeatherPayload(args);
  const apiMappedInput = mapWeatherResponseToModelInput(
    weatherPayload,
    args.latitude,
    args.longitude,
    args.date
  );
  const rawRecord = modelInputToRawRecord(apiMappedInput);
  const rawFeatureMap = buildFeatureMap(rawRecord, new Date(apiMappedInput.date));
  const { completedFeatureMap, missingFeatures } = imputeFeatureMap(rawFeatureMap, model.imputationMeans);
  const vector = normalizeVector(completedFeatureMap, model.normalization);
  const probability = predictProbability(vector, model);

  const result = {
    // Include apiMappedInput and missingFeaturesImputed so users can see which
    // fields came from live weather and which fell back to training means.
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
    proxyRiskProbability: probability,
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
