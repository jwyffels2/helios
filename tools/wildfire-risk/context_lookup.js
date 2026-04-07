"use strict";

// Looks up static or slowly changing context features for a coordinate/date.
// It builds an index from the local FIRMS feature join and returns the nearest
// seasonal match so live scoring can reuse vegetation and drought context even
// when the weather API does not provide those fields directly.

const path = require("path");
const {
  loadCsv,
  parseDateValue,
  parseNumber,
} = require("./common");

const DEFAULT_CONTEXT_CSV = "c:\\Users\\Leonard\\Desktop\\firms_ee_feature_join.csv";

function dayOfYear(date) {
  const start = new Date(Date.UTC(date.getUTCFullYear(), 0, 0));
  const diff = date - start;
  return Math.floor(diff / 86400000);
}

function circularDayDifference(left, right) {
  const diff = Math.abs(left - right);
  return Math.min(diff, 366 - diff);
}

function haversineKm(lat1, lon1, lat2, lon2) {
  const toRadians = (value) => (value * Math.PI) / 180;
  const earthRadiusKm = 6371;
  const dLat = toRadians(lat2 - lat1);
  const dLon = toRadians(lon2 - lon1);
  const a = Math.sin(dLat / 2) ** 2
    + Math.cos(toRadians(lat1)) * Math.cos(toRadians(lat2)) * Math.sin(dLon / 2) ** 2;
  return 2 * earthRadiusKm * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

function normalizeContextRow(row) {
  const date = parseDateValue(row.date);
  const lat = parseNumber(row.lat);
  const long = parseNumber(row.long);

  if (!date || lat === null || long === null) {
    return null;
  }

  return {
    date,
    doy: dayOfYear(date),
    lat,
    long,
    temperatureSurface: parseNumber(row.Temperature_surface),
    precipitation: parseNumber(row.precipitation),
    tmax: parseNumber(row.tmax),
    tmin: parseNumber(row.tmin),
    vegetationType: parseNumber(row.Vegetation_Type_surface),
    vegetation: parseNumber(row.Vegetation_surface),
    pdsi: parseNumber(row.pdsi),
    windU: parseNumber(row["u-component_of_wind_hybrid"]),
    windV: parseNumber(row["v-component_of_wind_hybrid"]),
  };
}

function buildContextIndex(csvPath = DEFAULT_CONTEXT_CSV) {
  const rows = loadCsv(path.resolve(csvPath))
    .map(normalizeContextRow)
    .filter(Boolean);

  const byDayOfYear = new Map();
  for (const row of rows) {
    if (!byDayOfYear.has(row.doy)) {
      byDayOfYear.set(row.doy, []);
    }
    byDayOfYear.get(row.doy).push(row);
  }

  return {
    csvPath: path.resolve(csvPath),
    rows,
    byDayOfYear,
  };
}

function lookupNearestContext(index, candidate, options = {}) {
  const dayWindow = options.dayWindow ?? 14;
  const dayPenaltyKm = options.dayPenaltyKm ?? 5;
  const date = parseDateValue(candidate.date) ?? new Date();
  const candidateDoy = dayOfYear(date);
  const lat = Number(candidate.lat);
  const long = Number(candidate.long);
  let best = null;
  let bestScore = Number.POSITIVE_INFINITY;

  for (let offset = -dayWindow; offset <= dayWindow; offset += 1) {
    let day = candidateDoy + offset;
    while (day < 1) {
      day += 366;
    }
    while (day > 366) {
      day -= 366;
    }

    const rows = index.byDayOfYear.get(day) ?? [];
    for (const row of rows) {
      const distanceKm = haversineKm(lat, long, row.lat, row.long);
      const score = distanceKm + (circularDayDifference(candidateDoy, row.doy) * dayPenaltyKm);
      if (score < bestScore) {
        bestScore = score;
        best = row;
      }
    }
  }

  if (!best) {
    for (const row of index.rows) {
      const distanceKm = haversineKm(lat, long, row.lat, row.long);
      if (distanceKm < bestScore) {
        bestScore = distanceKm;
        best = row;
      }
    }
  }

  const result = best
    ? {
        vegetationType: best.vegetationType,
        vegetation: best.vegetation,
        pdsi: best.pdsi,
      }
    : {
        vegetationType: null,
        vegetation: null,
        pdsi: null,
      };

  if (options.includeWeatherProxies) {
    Object.assign(result, best
      ? {
          temperatureSurface: best.temperatureSurface,
          precipitation: best.precipitation,
          tmax: best.tmax,
          tmin: best.tmin,
          windU: best.windU,
          windV: best.windV,
        }
      : {
          temperatureSurface: null,
          precipitation: null,
          tmax: null,
          tmin: null,
          windU: null,
          windV: null,
        });
  }

  return result;
}

module.exports = {
  DEFAULT_CONTEXT_CSV,
  buildContextIndex,
  lookupNearestContext,
};
