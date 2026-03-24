"use strict";

// Defines the feature schema for the true wildfire classifier.
// This file is the shared contract between dataset generation, training, and
// inference so every stage builds the same numeric feature vector.

const {
  parseDateValue,
  parseNumber,
} = require("./common");

const TRUE_FEATURE_NAMES = [
  "lat",
  "long",
  "elevation",
  "temperatureSurface",
  "relativeHumiditySurface",
  "dewPointSurface",
  "precipitation",
  "tmax",
  "tmin",
  "vegetationType",
  "vegetation",
  "pdsi",
  "windU",
  "windV",
  "surfacePressure",
  "cloudCover",
  "soilTemperatureSurface",
  "soilMoistureSurface",
  "windSpeed",
  "dayOfYearSin",
  "dayOfYearCos",
];

function dayOfYear(date) {
  const start = new Date(Date.UTC(date.getUTCFullYear(), 0, 0));
  const diff = date - start;
  return Math.floor(diff / 86400000);
}

function buildTrueClassifierFeatureMap(record, fallbackDate) {
  const featureMap = {
    lat: parseNumber(record.lat),
    long: parseNumber(record.long),
    elevation: parseNumber(record.elevation),
    temperatureSurface: parseNumber(record.temperatureSurface ?? record.Temperature_surface),
    relativeHumiditySurface: parseNumber(record.relativeHumiditySurface ?? record.relative_humidity_2m),
    dewPointSurface: parseNumber(record.dewPointSurface ?? record.dew_point_2m),
    precipitation: parseNumber(record.precipitation),
    tmax: parseNumber(record.tmax),
    tmin: parseNumber(record.tmin),
    vegetationType: parseNumber(record.vegetationType ?? record.Vegetation_Type_surface),
    vegetation: parseNumber(record.vegetation ?? record.Vegetation_surface),
    pdsi: parseNumber(record.pdsi),
    windU: parseNumber(record.windU ?? record["u-component_of_wind_hybrid"]),
    windV: parseNumber(record.windV ?? record["v-component_of_wind_hybrid"]),
    surfacePressure: parseNumber(record.surfacePressure ?? record.surface_pressure),
    cloudCover: parseNumber(record.cloudCover ?? record.cloud_cover),
    soilTemperatureSurface: parseNumber(record.soilTemperatureSurface ?? record.soil_temperature_0_to_7cm),
    soilMoistureSurface: parseNumber(record.soilMoistureSurface ?? record.soil_moisture_0_to_7cm),
  };

  const dateValue = parseDateValue(record.date) || fallbackDate || new Date();
  const doy = dayOfYear(dateValue);
  const angle = (2 * Math.PI * doy) / 365.25;

  if (featureMap.windU !== null && featureMap.windV !== null) {
    featureMap.windSpeed = Math.sqrt((featureMap.windU ** 2) + (featureMap.windV ** 2));
  } else {
    featureMap.windSpeed = null;
  }

  featureMap.dayOfYearSin = Math.sin(angle);
  featureMap.dayOfYearCos = Math.cos(angle);

  return featureMap;
}

module.exports = {
  TRUE_FEATURE_NAMES,
  buildTrueClassifierFeatureMap,
};
