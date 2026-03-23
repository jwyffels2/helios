"use strict";

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

async function fetchOpenMeteoArchive(latitude, longitude, isoDateTime) {
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

  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`Open-Meteo archive request failed with status ${response.status}`);
  }

  const payload = await response.json();
  const hourly = payload.hourly ?? {};
  const hourlyIndex = nearestHourlyIndex(hourly.time, targetDate);
  const windSpeed = hourlyIndex >= 0 ? hourly.wind_speed_10m?.[hourlyIndex] : null;
  const windDirection = hourlyIndex >= 0 ? hourly.wind_direction_10m?.[hourlyIndex] : null;
  const { windU, windV } = windComponentsFromSpeedAndDirection(windSpeed, windDirection);

  return {
    lat: latitude,
    long: longitude,
    date: targetDate.toISOString(),
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

  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`Open-Meteo forecast request failed with status ${response.status}`);
  }

  return response.json();
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
  fetchOpenMeteoArchive,
  fetchOpenMeteoForecast,
  mapForecastPayloadToTrueClassifierInput,
  windComponentsFromSpeedAndDirection,
};
