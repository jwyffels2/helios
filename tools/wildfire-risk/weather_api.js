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
  if (!value) {
    return null;
  }

  return value.endsWith("Z") ? value : `${value}Z`;
}

function firstValue(array) {
  return Array.isArray(array) && array.length > 0 ? array[0] : null;
}

function windComponentsFromSpeedAndDirection(speed, directionDegrees) {
  if (!Number.isFinite(speed) || !Number.isFinite(directionDegrees)) {
    return { windU: null, windV: null };
  }

  const angle = (directionDegrees * Math.PI) / 180;
  return {
    windU: -speed * Math.sin(angle),
    windV: -speed * Math.cos(angle),
  };
}

function nearestHourlyIndex(times, targetDate) {
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

function ensureDirectoryExists(directoryPath) {
  fs.mkdirSync(directoryPath, { recursive: true });
}

function sleep(milliseconds) {
  return new Promise((resolve) => {
    setTimeout(resolve, milliseconds);
  });
}

function buildCachePath(cacheKey, url) {
  const hash = crypto.createHash("sha1").update(url.toString()).digest("hex");
  return path.join(DEFAULT_CACHE_DIR, `${cacheKey}-${hash}.json`);
}

function readCache(cachePath, maxAgeMs = Number.POSITIVE_INFINITY) {
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
  ensureDirectoryExists(path.dirname(cachePath));
  fs.writeFileSync(cachePath, `${JSON.stringify({
    cachedAt: new Date().toISOString(),
    url: url.toString(),
    payload,
  }, null, 2)}\n`, "utf8");
}

async function fetchJsonWithCache(url, cacheKey, maxAgeMs = Number.POSITIVE_INFINITY, requestOptions = {}) {
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
  const targetDate = new Date(isoDateTime);
  const dateString = targetDate.toISOString().slice(0, 10);
  const url = new URL("https://archive-api.open-meteo.com/v1/archive");
  url.searchParams.set("latitude", String(latitude));
  url.searchParams.set("longitude", String(longitude));
  url.searchParams.set("start_date", dateString);
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

  return {
    lat: latitude,
    long: longitude,
    date: targetDate.toISOString(),
    elevation: payload.elevation ?? null,
    temperatureSurface: hourlyIndex >= 0 ? hourly.temperature_2m?.[hourlyIndex] ?? null : null,
    relativeHumiditySurface: hourlyIndex >= 0 ? hourly.relative_humidity_2m?.[hourlyIndex] ?? null : null,
    dewPointSurface: hourlyIndex >= 0 ? hourly.dew_point_2m?.[hourlyIndex] ?? null : null,
    precipitation: hourlyIndex >= 0 ? hourly.precipitation?.[hourlyIndex] ?? null : null,
    tmax: firstValue(payload.daily?.temperature_2m_max),
    tmin: firstValue(payload.daily?.temperature_2m_min),
    windU,
    windV,
    surfacePressure: hourlyIndex >= 0 ? hourly.surface_pressure?.[hourlyIndex] ?? null : null,
    cloudCover: hourlyIndex >= 0 ? hourly.cloud_cover?.[hourlyIndex] ?? null : null,
    soilTemperatureSurface: hourlyIndex >= 0 ? hourly.soil_temperature_0_to_7cm?.[hourlyIndex] ?? null : null,
    soilMoistureSurface: hourlyIndex >= 0 ? hourly.soil_moisture_0_to_7cm?.[hourlyIndex] ?? null : null,
  };
}

async function fetchOpenMeteoForecast(latitude, longitude) {
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

  return fetchJsonWithCache(url, "forecast", FORECAST_CACHE_MAX_AGE_MS, {
    requestDelayMs: 100,
  });
}

function mapForecastPayloadToTrueClassifierInput(payload, latitude, longitude, dateOverride) {
  const current = payload.current ?? {};
  const daily = payload.daily ?? {};
  const { windU, windV } = windComponentsFromSpeedAndDirection(
    current.wind_speed_10m,
    current.wind_direction_10m
  );

  return {
    lat: latitude,
    long: longitude,
    date: dateOverride ?? (current.time ? `${current.time}Z` : null) ?? new Date().toISOString(),
    elevation: payload.elevation ?? null,
    temperatureSurface: current.temperature_2m ?? null,
    relativeHumiditySurface: current.relative_humidity_2m ?? null,
    dewPointSurface: current.dew_point_2m ?? null,
    precipitation: current.precipitation ?? null,
    tmax: firstValue(daily.temperature_2m_max),
    tmin: firstValue(daily.temperature_2m_min),
    windU,
    windV,
    surfacePressure: current.surface_pressure ?? null,
    cloudCover: current.cloud_cover ?? null,
    soilTemperatureSurface: current.soil_temperature_0_to_7cm ?? null,
    soilMoistureSurface: current.soil_moisture_0_to_7cm ?? null,
  };
}

module.exports = {
  DEFAULT_CACHE_DIR,
  fetchOpenMeteoArchive,
  fetchOpenMeteoForecast,
  mapForecastPayloadToTrueClassifierInput,
  windComponentsFromSpeedAndDirection,
};
