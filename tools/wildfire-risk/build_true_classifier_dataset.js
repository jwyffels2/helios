"use strict";

// Builds the labeled training dataset for the true wildfire classifier.
// This script samples positive fire detections, generates explicit non-fire
// negatives, enriches both with historical weather/context data, and writes
// checkpointed progress so long runs can resume after interruptions.

const path = require("path");
const {
  loadCsv,
  parseDateValue,
  parseNumber,
  saveJson,
} = require("./common");
const {
  fetchOpenMeteoArchive,
} = require("./weather_api");
const {
  DEFAULT_CONTEXT_CSV,
  buildContextIndex,
  lookupNearestContext,
} = require("./context_lookup");

const FEATURE_SCHEMA_VERSION = 2;

function parseArguments(argv) {
  const args = {
    csv: "c:\\Users\\Leonard\\Desktop\\firms_ee_feature_join.csv",
    output: path.join(__dirname, "output", "true_classifier_dataset.json"),
    positives: 25,
    negatives: 25,
    seed: 42,
    minDistanceKm: 25,
    timeBufferDays: 1,
    maxAttempts: 5000,
    contextCsv: DEFAULT_CONTEXT_CSV,
    checkpointEvery: 25,
    requestDelayMs: 250,
    maxRetries: 6,
    initialBackoffMs: 2000,
    hardNegativeRatio: 0.5,
    hardNegativePoolMultiplier: 4,
    resume: true,
  };

  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];
    if (token === "--csv") {
      args.csv = argv[index + 1];
      index += 1;
    } else if (token === "--output") {
      args.output = argv[index + 1];
      index += 1;
    } else if (token === "--positives") {
      args.positives = Number(argv[index + 1]);
      index += 1;
    } else if (token === "--negatives") {
      args.negatives = Number(argv[index + 1]);
      index += 1;
    } else if (token === "--seed") {
      args.seed = Number(argv[index + 1]);
      index += 1;
    } else if (token === "--min-distance-km") {
      args.minDistanceKm = Number(argv[index + 1]);
      index += 1;
    } else if (token === "--time-buffer-days") {
      args.timeBufferDays = Number(argv[index + 1]);
      index += 1;
    } else if (token === "--max-attempts") {
      args.maxAttempts = Number(argv[index + 1]);
      index += 1;
    } else if (token === "--context-csv") {
      args.contextCsv = argv[index + 1];
      index += 1;
    } else if (token === "--checkpoint-every") {
      args.checkpointEvery = Number(argv[index + 1]);
      index += 1;
    } else if (token === "--request-delay-ms") {
      args.requestDelayMs = Number(argv[index + 1]);
      index += 1;
    } else if (token === "--max-retries") {
      args.maxRetries = Number(argv[index + 1]);
      index += 1;
    } else if (token === "--initial-backoff-ms") {
      args.initialBackoffMs = Number(argv[index + 1]);
      index += 1;
    } else if (token === "--hard-negative-ratio") {
      args.hardNegativeRatio = Number(argv[index + 1]);
      index += 1;
    } else if (token === "--hard-negative-pool-multiplier") {
      args.hardNegativePoolMultiplier = Number(argv[index + 1]);
      index += 1;
    } else if (token === "--fresh") {
      args.resume = false;
    } else if (token === "--resume") {
      args.resume = true;
    }
  }

  return args;
}

function createRng(seed) {
  let state = seed >>> 0;
  return () => {
    state = (1664525 * state + 1013904223) >>> 0;
    return state / 0x100000000;
  };
}

function sampleWithoutReplacement(items, count, rng) {
  const cloned = [...items];
  for (let index = cloned.length - 1; index > 0; index -= 1) {
    const swapIndex = Math.floor(rng() * (index + 1));
    [cloned[index], cloned[swapIndex]] = [cloned[swapIndex], cloned[index]];
  }

  return cloned.slice(0, Math.min(count, cloned.length));
}

function toDateKey(date) {
  return date.toISOString().slice(0, 10);
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

function buildPositiveIndex(records) {
  const byDate = new Map();

  for (const record of records) {
    const key = toDateKey(record.date);
    if (!byDate.has(key)) {
      byDate.set(key, []);
    }
    byDate.get(key).push(record);
  }

  return byDate;
}

function isFarFromPositives(candidate, positiveIndex, timeBufferDays, minDistanceKm) {
  for (let dayOffset = -timeBufferDays; dayOffset <= timeBufferDays; dayOffset += 1) {
    const date = new Date(candidate.date);
    date.setUTCDate(date.getUTCDate() + dayOffset);
    const dayRecords = positiveIndex.get(toDateKey(date));
    if (!dayRecords) {
      continue;
    }

    for (const positive of dayRecords) {
      const distance = haversineKm(candidate.lat, candidate.long, positive.lat, positive.long);
      if (distance < minDistanceKm) {
        return false;
      }
    }
  }

  return true;
}

function clamp(value, minimum, maximum) {
  return Math.max(minimum, Math.min(maximum, value));
}

function generateNegativeCandidate(anchor, bounds, rng) {
  const angle = rng() * 2 * Math.PI;
  const radiusKm = 30 + (rng() * 170);
  const latDelta = (radiusKm / 111) * Math.cos(angle);
  const lonScale = Math.max(0.2, Math.cos((anchor.lat * Math.PI) / 180));
  const lonDelta = (radiusKm / (111 * lonScale)) * Math.sin(angle);

  const date = new Date(anchor.date);
  date.setUTCDate(date.getUTCDate() + Math.floor((rng() * 21) - 10));

  return {
    lat: clamp(anchor.lat + latDelta, bounds.minLat, bounds.maxLat),
    long: clamp(anchor.long + lonDelta, bounds.minLong, bounds.maxLong),
    date,
  };
}

function dayOfYear(date) {
  const start = new Date(Date.UTC(date.getUTCFullYear(), 0, 0));
  const diff = date - start;
  return Math.floor(diff / 86400000);
}

function normalizeUnit(value, minimum, maximum) {
  if (!Number.isFinite(value) || maximum <= minimum) {
    return 0.5;
  }
  return clamp((value - minimum) / (maximum - minimum), 0, 1);
}

function firstFinite(...values) {
  return values.find((value) => Number.isFinite(value)) ?? null;
}

function seasonalFireScore(date) {
  const doy = dayOfYear(date);
  if (doy >= 150 && doy <= 280) {
    return 1;
  }
  if ((doy >= 100 && doy < 150) || (doy > 280 && doy <= 320)) {
    return 0.6;
  }
  return 0.25;
}

function hardNegativeScore(candidate) {
  const temperature = firstFinite(candidate.temperatureSurface, candidate.tmax, candidate.tmin);
  const precipitation = firstFinite(candidate.precipitation);
  const pdsi = firstFinite(candidate.pdsi);
  const vegetation = firstFinite(candidate.vegetation);
  const windU = firstFinite(candidate.windU);
  const windV = firstFinite(candidate.windV);
  const windSpeed = windU !== null && windV !== null
    ? Math.sqrt((windU ** 2) + (windV ** 2))
    : null;

  const hotScore = normalizeUnit(temperature, 15, 40);
  const dryScore = pdsi === null ? 0.5 : normalizeUnit(-pdsi, 0, 6);
  const lowPrecipScore = precipitation === null ? 0.5 : 1 - normalizeUnit(precipitation, 0, 10);
  const vegetationScore = normalizeUnit(vegetation, 0, 100);
  const windScore = normalizeUnit(windSpeed, 0, 12);
  const seasonScore = seasonalFireScore(candidate.date);

  return (
    (0.30 * hotScore)
    + (0.25 * dryScore)
    + (0.15 * lowPrecipScore)
    + (0.15 * vegetationScore)
    + (0.10 * windScore)
    + (0.05 * seasonScore)
  );
}

function negativeCandidateKey(candidate) {
  const lat = Number(candidate.lat).toFixed(4);
  const long = Number(candidate.long).toFixed(4);
  return `${toDateKey(candidate.date)}|${lat}|${long}`;
}

function generateNegativeCandidatePool(count, positiveCandidates, bounds, rng, positiveIndex, args, contextIndex) {
  const candidates = [];
  const seenKeys = new Set();
  let attempts = 0;

  while (candidates.length < count && attempts < args.maxAttempts) {
    attempts += 1;
    const anchor = positiveCandidates[Math.floor(rng() * positiveCandidates.length)];
    const candidate = generateNegativeCandidate(anchor, bounds, rng);
    if (!isFarFromPositives(candidate, positiveIndex, args.timeBufferDays, args.minDistanceKm)) {
      continue;
    }

    const key = negativeCandidateKey(candidate);
    if (seenKeys.has(key)) {
      continue;
    }

    const withContext = {
      ...candidate,
      ...lookupNearestContext(contextIndex, candidate, { includeWeatherProxies: true }),
    };

    seenKeys.add(key);
    candidates.push({
      ...withContext,
      hardNegativeScore: hardNegativeScore(withContext),
    });
  }

  return {
    attempts,
    candidates,
  };
}

function selectNegatives(candidatePool, args, rng) {
  const hardNegativeCount = Math.min(
    args.negatives,
    Math.max(0, Math.round(args.negatives * clamp(args.hardNegativeRatio, 0, 1)))
  );
  const sortedByHardness = [...candidatePool].sort((left, right) => right.hardNegativeScore - left.hardNegativeScore);
  const hardNegatives = sortedByHardness.slice(0, hardNegativeCount)
    .map((candidate) => ({ ...candidate, negativeKind: "hard" }));
  const hardKeys = new Set(hardNegatives.map(negativeCandidateKey));
  const remaining = candidatePool.filter((candidate) => !hardKeys.has(negativeCandidateKey(candidate)));
  const randomNegatives = sampleWithoutReplacement(remaining, args.negatives - hardNegatives.length, rng)
    .map((candidate) => ({ ...candidate, negativeKind: "random" }));
  return [...hardNegatives, ...randomNegatives];
}

async function enrichSample(sample, label) {
  const weather = await fetchOpenMeteoArchive(sample.lat, sample.long, sample.date.toISOString(), sample.requestOptions);
  return {
    label,
    lat: sample.lat,
    long: sample.long,
    date: sample.date.toISOString(),
    negativeKind: sample.negativeKind ?? null,
    hardNegativeScore: sample.hardNegativeScore ?? null,
    vegetationType: sample.vegetationType ?? null,
    vegetation: sample.vegetation ?? null,
    pdsi: sample.pdsi ?? null,
    ...weather,
  };
}

function sampleKey(sample) {
  const lat = Number(sample.lat).toFixed(6);
  const long = Number(sample.long).toFixed(6);
  const date = new Date(sample.date).toISOString();
  return `${sample.label}|${date}|${lat}|${long}`;
}

function buildGenerationParameters(args, contextIndex) {
  return {
    featureSchemaVersion: FEATURE_SCHEMA_VERSION,
    positives: args.positives,
    negatives: args.negatives,
    minDistanceKm: args.minDistanceKm,
    timeBufferDays: args.timeBufferDays,
    hardNegativeRatio: args.hardNegativeRatio,
    hardNegativePoolMultiplier: args.hardNegativePoolMultiplier,
    seed: args.seed,
    contextCsv: contextIndex.csvPath,
  };
}

function progressSummary(samples) {
  const positiveCount = samples.filter((sample) => sample.label === 1).length;
  const negativeCount = samples.length - positiveCount;
  return {
    positiveCount,
    negativeCount,
    totalCount: samples.length,
  };
}

function saveProgressDocument(args, contextIndex, samples, status, note = null) {
  const document = {
    datasetType: "historical_fire_vs_background",
    createdAt: new Date().toISOString(),
    status,
    note,
    sourceCsv: path.resolve(args.csv),
    generationParameters: buildGenerationParameters(args, contextIndex),
    progress: progressSummary(samples),
    samples,
  };

  saveJson(args.output, document);
}

function generationParametersMatch(existingDocument, args, contextIndex) {
  const existing = existingDocument?.generationParameters ?? {};
  const current = buildGenerationParameters(args, contextIndex);

  return existing.positives === current.positives
    && existing.featureSchemaVersion === current.featureSchemaVersion
    && existing.negatives === current.negatives
    && existing.minDistanceKm === current.minDistanceKm
    && existing.timeBufferDays === current.timeBufferDays
    && existing.hardNegativeRatio === current.hardNegativeRatio
    && existing.hardNegativePoolMultiplier === current.hardNegativePoolMultiplier
    && existing.seed === current.seed
    && existing.contextCsv === current.contextCsv
    && path.resolve(existingDocument.sourceCsv ?? "") === path.resolve(args.csv);
}

async function main() {
  const args = parseArguments(process.argv.slice(2));
  const rng = createRng(args.seed);
  const rawRows = loadCsv(args.csv);
  const contextIndex = buildContextIndex(args.contextCsv);
  const positiveCandidates = rawRows
    .map((row) => {
      const date = parseDateValue(row.date);
      const lat = parseNumber(row.lat);
      const long = parseNumber(row.long);
      if (!date || lat === null || long === null) {
        return null;
      }

      return {
        date,
        lat,
        long,
        vegetationType: parseNumber(row.Vegetation_Type_surface),
        vegetation: parseNumber(row.Vegetation_surface),
        pdsi: parseNumber(row.pdsi),
      };
    })
    .filter(Boolean);

  const bounds = positiveCandidates.reduce((state, record) => ({
    minLat: Math.min(state.minLat, record.lat),
    maxLat: Math.max(state.maxLat, record.lat),
    minLong: Math.min(state.minLong, record.long),
    maxLong: Math.max(state.maxLong, record.long),
  }), {
    minLat: Number.POSITIVE_INFINITY,
    maxLat: Number.NEGATIVE_INFINITY,
    minLong: Number.POSITIVE_INFINITY,
    maxLong: Number.NEGATIVE_INFINITY,
  });

  const selectedPositives = sampleWithoutReplacement(positiveCandidates, args.positives, rng);
  const positiveIndex = buildPositiveIndex(positiveCandidates);
  const hardNegativeCount = Math.min(
    args.negatives,
    Math.max(0, Math.round(args.negatives * clamp(args.hardNegativeRatio, 0, 1)))
  );
  const negativePoolTarget = Math.max(
    args.negatives,
    args.negatives + (hardNegativeCount * (Math.max(1, args.hardNegativePoolMultiplier) - 1))
  );
  const { attempts, candidates: negativePool } = generateNegativeCandidatePool(
    negativePoolTarget,
    positiveCandidates,
    bounds,
    rng,
    positiveIndex,
    args,
    contextIndex
  );
  const negatives = selectNegatives(negativePool, args, rng);

  if (negatives.length < args.negatives) {
    throw new Error(`Only generated ${negatives.length} negatives after ${args.maxAttempts} attempts.`);
  }

  let samples = [];
  if (args.resume) {
    try {
      const existing = require("./common").loadJson(args.output);
      if (generationParametersMatch(existing, args, contextIndex)) {
        samples = Array.isArray(existing.samples) ? existing.samples : [];
      }
    } catch {
      samples = [];
    }
  }

  const completedKeys = new Set(samples.map(sampleKey));
  const plannedSamples = [
    ...selectedPositives.map((positive) => ({ ...positive, label: 1 })),
    ...negatives.map((negative) => ({ ...negative, label: 0 })),
  ];
  const plannedTotal = plannedSamples.length;

  if (samples.length >= plannedTotal) {
    saveProgressDocument(args, contextIndex, samples, "complete", "dataset already complete");
    console.log(`Dataset already complete at ${path.resolve(args.output)}`);
    console.log(`Positive samples: ${progressSummary(samples).positiveCount}`);
    console.log(`Negative samples: ${progressSummary(samples).negativeCount}`);
    return;
  }

  let sinceCheckpoint = 0;
  for (const plannedSample of plannedSamples) {
    if (completedKeys.has(sampleKey(plannedSample))) {
      continue;
    }

    try {
      const enriched = await enrichSample(
        {
          ...plannedSample,
          requestOptions: {
            requestDelayMs: args.requestDelayMs,
            maxRetries: args.maxRetries,
            initialBackoffMs: args.initialBackoffMs,
          },
        },
        plannedSample.label
      );
      samples.push(enriched);
      completedKeys.add(sampleKey(enriched));
      sinceCheckpoint += 1;

      if (sinceCheckpoint >= args.checkpointEvery) {
        saveProgressDocument(args, contextIndex, samples, "in_progress");
        console.log(`Checkpointed ${samples.length}/${plannedTotal} samples to ${path.resolve(args.output)}`);
        sinceCheckpoint = 0;
      }
    } catch (error) {
      saveProgressDocument(args, contextIndex, samples, "in_progress", error.message);
      throw new Error(`${error.message}. Progress saved to ${path.resolve(args.output)}.`);
    }
  }

  samples.sort((left, right) => new Date(left.date) - new Date(right.date));
  saveProgressDocument(args, contextIndex, samples, "complete");
  console.log(`Saved dataset to ${path.resolve(args.output)}`);
  console.log(`Positive samples: ${progressSummary(samples).positiveCount}`);
  console.log(`Negative samples: ${progressSummary(samples).negativeCount}`);
}

main().catch((error) => {
  console.error(error.message);
  process.exitCode = 1;
});
