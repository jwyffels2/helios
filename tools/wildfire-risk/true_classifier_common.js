"use strict";

const {
  parseDateValue,
  parseNumber,
} = require("./common");

const TRUE_FEATURE_NAMES = [
  "lat",
  "long",
  "temperatureSurface",
  "precipitation",
  "tmax",
  "tmin",
  "windU",
  "windV",
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
    temperatureSurface: parseNumber(record.temperatureSurface ?? record.Temperature_surface),
    precipitation: parseNumber(record.precipitation),
    tmax: parseNumber(record.tmax),
    tmin: parseNumber(record.tmin),
    windU: parseNumber(record.windU ?? record["u-component_of_wind_hybrid"]),
    windV: parseNumber(record.windV ?? record["v-component_of_wind_hybrid"]),
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
