"use strict";

// Wraps Open-Meteo access for the wildfire model pipeline.
// This file owns request shaping, local response caching, retry/backoff
// behavior, and mapping raw weather payloads into the model's feature names.

const crypto = require("crypto");
const fs = require("fs");
const path = require("path");

const DEFAULT_CACHE_DIR = path.join(__dirname, "output", "cache", "open-meteo");
const FORECAST_CACHE_MAX_AGE_MS = 60 * 60 * 1000;
let nextRequestAllowedAt = 0;

function toIsoHourString(value) {
  // Open-Meteo hourly timestamps are usually naive; normalize to explicit UTC.
  if (!value) {
    return null;
  }

  return value.endsWith("Z") ? value : `${value}Z`;
}

function firstValue(array) {
  return Array.isArray(array) && array.length > 0 ? array[0] : null;
}

function dateStringDaysBefore(date, daysBefore) {
  // Archive API expects YYYY-MM-DD windows.
  const copy = new Date(date);
  copy.setUTCDate(copy.getUTCDate() - daysBefore);
  return copy.toISOString().slice(0, 10);
}

function windComponentsFromSpeedAndDirection(speed, directionDegrees) {
  // Convert speed + heading into vector components used by the model.
  if (!Number.isFinite(speed) || !Number.isFinite(directionDegrees)) {
    return { windU: null, windV: null };
  }

  const angle = (directionDegrees * Math.PI) / 180;
  return {
    windU: -speed * Math.sin(angle),
    windV: -speed * Math.cos(angle),
  };
}

function finiteValues(values) {
  // Aggregates below ignore null/NaN API entries.
  return values.filter((value) => Number.isFinite(value));
}

function average(values) {
  const finite = finiteValues(values);
  if (finite.length === 0) {
    return null;
  }
  return finite.reduce((sum, value) => sum + value, 0) / finite.length;
}

function sum(values) {
  const finite = finiteValues(values);
  if (finite.length === 0) {
    return null;
  }
  return finite.reduce((total, value) => total + value, 0);
}

function maximum(values) {
  const finite = finiteValues(values);
  if (finite.length === 0) {
    return null;
  }
  return Math.max(...finite);
}

function nearestHourlyIndex(times, targetDate) {
  // Choose the hourly row nearest to the requested timestamp.
  if (!Array.isArray(times) || times.length === 0) {
    return -1;
  }

  let bestIndex = 0;
  let bestDistance = Number.POSITIVE_INFINITY;
  const targetTime = targetDate.getTime();

  for (let index = 0; index < times.length; index += 1) {
    const candidateTime = new Date(toIsoHourString(times[index])).getTime();
    const distance = Math.abs(candidateTime - targetTime);
    if (distance < bestDistance) {
      bestDistance = distance;
      bestIndex = index;
    }
  }

  return bestIndex;
}

function hourlyWindowValues(hourly, fieldName, targetDate, hoursBack) {
  // Slice values in (target-hoursBack, target] for lagged aggregates.
  const times = hourly.time;
  const values = hourly[fieldName];
  if (!Array.isArray(times) || !Array.isArray(values)) {
    return [];
  }

  const targetTime = targetDate.getTime();
  const startTime = targetTime - (hoursBack * 60 * 60 * 1000);
  const windowValues = [];

  for (let index = 0; index < times.length; index += 1) {
    const timestamp = new Date(toIsoHourString(times[index])).getTime();
    if (timestamp > startTime && timestamp <= targetTime) {
      windowValues.push(values[index]);
    }
  }

  return windowValues;
}

function dailyValueForDate(daily, fieldName, targetDate) {
  // Prefer same-day daily aggregate, otherwise fall back to first available.
  const times = daily?.time;
  const values = daily?.[fieldName];
  if (!Array.isArray(times) || !Array.isArray(values)) {
    return firstValue(values);
  }

  const targetDay = targetDate.toISOString().slice(0, 10);
  const index = times.findIndex((time) => time === targetDay);
  return index >= 0 ? values[index] ?? null : firstValue(values);
}

function laggedWeatherFeatures(hourly, targetDate) {
  // Build the temporal-context features used by the true classifier.
  const temperature24h = hourlyWindowValues(hourly, "temperature_2m", targetDate, 24);
  const temperature72h = hourlyWindowValues(hourly, "temperature_2m", targetDate, 72);
  const humidity24h = hourlyWindowValues(hourly, "relative_humidity_2m", targetDate, 24);
  const humidity72h = hourlyWindowValues(hourly, "relative_humidity_2m", targetDate, 72);
  const precipitation72h = hourlyWindowValues(hourly, "precipitation", targetDate, 72);
  const precipitation7d = hourlyWindowValues(hourly, "precipitation", targetDate, 24 * 7);
  const windSpeed7d = hourlyWindowValues(hourly, "wind_speed_10m", targetDate, 24 * 7);
  const soilMoisture72h = hourlyWindowValues(hourly, "soil_moisture_0_to_7cm", targetDate, 72);
  const soilMoisture7d = hourlyWindowValues(hourly, "soil_moisture_0_to_7cm", targetDate, 24 * 7);
  const soilTemperature7d = hourlyWindowValues(hourly, "soil_temperature_0_to_7cm", targetDate, 24 * 7);

  return {
    temperature24hAvg: average(temperature24h),
    temperature72hAvg: average(temperature72h),
    humidity24hAvg: average(humidity24h),
    humidity72hAvg: average(humidity72h),
    precipitation72hTotal: sum(precipitation72h),
    precipitation7dTotal: sum(precipitation7d),
    windSpeed7dMax: maximum(windSpeed7d),
    soilMoisture72hAvg: average(soilMoisture72h),
    soilMoisture7dAvg: average(soilMoisture7d),
    soilTemperature7dAvg: average(soilTemperature7d),
  };
}

function ensureDirectoryExists(directoryPath) {
  fs.mkdirSync(directoryPath, { recursive: true });
}

function sleep(milliseconds) {
  return new Promise((resolve) => {
    setTimeout(resolve, milliseconds);
  });
}

function buildCachePath(cacheKey, url) {
  // Cache key includes URL hash so query changes produce distinct entries.
  const hash = crypto.createHash("sha1").update(url.toString()).digest("hex");
  return path.join(DEFAULT_CACHE_DIR, `${cacheKey}-${hash}.json`);
}

function readCache(cachePath, maxAgeMs = Number.POSITIVE_INFINITY) {
  // Returns null when cache is missing, invalid, or stale.
  if (!fs.existsSync(cachePath)) {
    return null;
  }

  try {
    const cacheDocument = JSON.parse(fs.readFileSync(cachePath, "utf8"));
    const cachedAt = new Date(cacheDocument.cachedAt).getTime();
    const ageMs = Date.now() - cachedAt;
    if (!Number.isFinite(cachedAt) || ageMs > maxAgeMs) {
      return null;
    }

    return cacheDocument.payload ?? null;
  } catch {
    return null;
  }
}

function writeCache(cachePath, url, payload) {
  // Persist response payload with fetch timestamp for freshness checks.
  ensureDirectoryExists(path.dirname(cachePath));
  fs.writeFileSync(cachePath, `${JSON.stringify({
    cachedAt: new Date().toISOString(),
    url: url.toString(),
    payload,
  }, null, 2)}\n`, "utf8");
}

async function fetchJsonWithCache(url, cacheKey, maxAgeMs = Number.POSITIVE_INFINITY, requestOptions = {}) {
  // Shared network fetch wrapper:
  // cache-first read, then retried fetch with optional throttling/backoff.
  const cachePath = buildCachePath(cacheKey, url);
  const cachedPayload = readCache(cachePath, maxAgeMs);
  if (cachedPayload) {
    return cachedPayload;
  }

  const maxRetries = requestOptions.maxRetries ?? 6;
  const initialBackoffMs = requestOptions.initialBackoffMs ?? 2000;
  const requestDelayMs = requestOptions.requestDelayMs ?? 0;
  let backoffMs = initialBackoffMs;
  let lastError = null;

  for (let attempt = 0; attempt <= maxRetries; attempt += 1) {
    const now = Date.now();
    if (now < nextRequestAllowedAt) {
      await sleep(nextRequestAllowedAt - now);
    }
    nextRequestAllowedAt = Date.now() + requestDelayMs;

    try {
      const response = await fetch(url);
      if (response.ok) {
        const payload = await response.json();
        writeCache(cachePath, url, payload);
        return payload;
      }

      if (response.status !== 429 || attempt === maxRetries) {
        throw new Error(`Open-Meteo request failed with status ${response.status}`);
      }

      const retryAfterHeader = response.headers.get("retry-after");
      const retryAfterSeconds = Number(retryAfterHeader);
      const retryDelayMs = Number.isFinite(retryAfterSeconds) && retryAfterSeconds > 0
        ? retryAfterSeconds * 1000
        : backoffMs;
      await sleep(retryDelayMs);
      backoffMs = Math.min(backoffMs * 2, 60000);
    } catch (error) {
      lastError = error;
      if (attempt === maxRetries) {
        break;
      }
      await sleep(backoffMs);
      backoffMs = Math.min(backoffMs * 2, 60000);
    }
  }

  throw lastError ?? new Error("Open-Meteo request failed after retries.");
}

async function fetchOpenMeteoArchive(latitude, longitude, isoDateTime, requestOptions = {}) {
  // Historical query used during dataset generation.
  const targetDate = new Date(isoDateTime);
  const dateString = targetDate.toISOString().slice(0, 10);
  const url = new URL("https://archive-api.open-meteo.com/v1/archive");
  url.searchParams.set("latitude", String(latitude));
  url.searchParams.set("longitude", String(longitude));
  url.searchParams.set("start_date", dateStringDaysBefore(targetDate, 7));
  url.searchParams.set("end_date", dateString);
  url.searchParams.set("timezone", "UTC");
  url.searchParams.set("temperature_unit", "celsius");
  url.searchParams.set("precipitation_unit", "mm");
  url.searchParams.set("wind_speed_unit", "ms");
  url.searchParams.set(
    "hourly",
    [
      "temperature_2m",
      "relative_humidity_2m",
      "dew_point_2m",
      "precipitation",
      "wind_speed_10m",
      "wind_direction_10m",
      "surface_pressure",
      "cloud_cover",
      "soil_temperature_0_to_7cm",
      "soil_moisture_0_to_7cm",
    ].join(",")
  );
  url.searchParams.set("daily", "temperature_2m_max,temperature_2m_min");

  const payload = await fetchJsonWithCache(url, "archive", Number.POSITIVE_INFINITY, requestOptions);
  const hourly = payload.hourly ?? {};
  const hourlyIndex = nearestHourlyIndex(hourly.time, targetDate);
  const windSpeed = hourlyIndex >= 0 ? hourly.wind_speed_10m?.[hourlyIndex] : null;
  const windDirection = hourlyIndex >= 0 ? hourly.wind_direction_10m?.[hourlyIndex] : null;
  const { windU, windV } = windComponentsFromSpeedAndDirection(windSpeed, windDirection);
  const laggedFeatures = laggedWeatherFeatures(hourly, targetDate);

  return {
    lat: latitude,
    long: longitude,
    date: targetDate.toISOString(),
    elevation: payload.elevation ?? null,
    temperatureSurface: hourlyIndex >= 0 ? hourly.temperature_2m?.[hourlyIndex] ?? null : null,
    relativeHumiditySurface: hourlyIndex >= 0 ? hourly.relative_humidity_2m?.[hourlyIndex] ?? null : null,
    dewPointSurface: hourlyIndex >= 0 ? hourly.dew_point_2m?.[hourlyIndex] ?? null : null,
    precipitation: hourlyIndex >= 0 ? hourly.precipitation?.[hourlyIndex] ?? null : null,
    tmax: dailyValueForDate(payload.daily, "temperature_2m_max", targetDate),
    tmin: dailyValueForDate(payload.daily, "temperature_2m_min", targetDate),
    windU,
    windV,
    surfacePressure: hourlyIndex >= 0 ? hourly.surface_pressure?.[hourlyIndex] ?? null : null,
    cloudCover: hourlyIndex >= 0 ? hourly.cloud_cover?.[hourlyIndex] ?? null : null,
    soilTemperatureSurface: hourlyIndex >= 0 ? hourly.soil_temperature_0_to_7cm?.[hourlyIndex] ?? null : null,
    soilMoistureSurface: hourlyIndex >= 0 ? hourly.soil_moisture_0_to_7cm?.[hourlyIndex] ?? null : null,
    ...laggedFeatures,
  };
}

async function fetchOpenMeteoForecast(latitude, longitude) {
  // Near-real-time forecast/current query used for live and batch inference.
  const url = new URL("https://api.open-meteo.com/v1/forecast");
  url.searchParams.set("latitude", String(latitude));
  url.searchParams.set("longitude", String(longitude));
  url.searchParams.set("timezone", "UTC");
  url.searchParams.set("past_days", "7");
  url.searchParams.set("forecast_days", "1");
  url.searchParams.set("temperature_unit", "celsius");
  url.searchParams.set("precipitation_unit", "mm");
  url.searchParams.set("wind_speed_unit", "ms");
  url.searchParams.set(
    "current",
    [
      "temperature_2m",
      "relative_humidity_2m",
      "dew_point_2m",
      "precipitation",
      "wind_speed_10m",
      "wind_direction_10m",
      "surface_pressure",
      "cloud_cover",
      "soil_temperature_0_to_7cm",
      "soil_moisture_0_to_7cm",
    ].join(",")
  );
  url.searchParams.set(
    "hourly",
    [
      "temperature_2m",
      "relative_humidity_2m",
      "precipitation",
      "wind_speed_10m",
      "soil_temperature_0_to_7cm",
      "soil_moisture_0_to_7cm",
    ].join(",")
  );
  url.searchParams.set("daily", "temperature_2m_max,temperature_2m_min");

  return fetchJsonWithCache(url, "forecast", FORECAST_CACHE_MAX_AGE_MS, {
    requestDelayMs: 100,
  });
}

function mapForecastPayloadToTrueClassifierInput(payload, latitude, longitude, dateOverride) {
  // Map forecast payload to the canonical true-classifier input schema.
  const current = payload.current ?? {};
  const daily = payload.daily ?? {};
  const targetDate = new Date(dateOverride ?? (current.time ? `${current.time}Z` : null) ?? new Date().toISOString());
  const { windU, windV } = windComponentsFromSpeedAndDirection(
    current.wind_speed_10m,
    current.wind_direction_10m
  );
  const laggedFeatures = laggedWeatherFeatures(payload.hourly ?? {}, targetDate);

  return {
    lat: latitude,
    long: longitude,
    date: targetDate.toISOString(),
    elevation: payload.elevation ?? null,
    temperatureSurface: current.temperature_2m ?? null,
    relativeHumiditySurface: current.relative_humidity_2m ?? null,
    dewPointSurface: current.dew_point_2m ?? null,
    precipitation: current.precipitation ?? null,
    tmax: dailyValueForDate(daily, "temperature_2m_max", targetDate),
    tmin: dailyValueForDate(daily, "temperature_2m_min", targetDate),
    windU,
    windV,
    surfacePressure: current.surface_pressure ?? null,
    cloudCover: current.cloud_cover ?? null,
    soilTemperatureSurface: current.soil_temperature_0_to_7cm ?? null,
    soilMoistureSurface: current.soil_moisture_0_to_7cm ?? null,
    ...laggedFeatures,
  };
}

module.exports = {
  DEFAULT_CACHE_DIR,
  fetchOpenMeteoArchive,
  fetchOpenMeteoForecast,
  mapForecastPayloadToTrueClassifierInput,
  windComponentsFromSpeedAndDirection,
};
