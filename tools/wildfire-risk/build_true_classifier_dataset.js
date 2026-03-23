"use strict";

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

async function enrichSample(sample, label) {
  const weather = await fetchOpenMeteoArchive(sample.lat, sample.long, sample.date.toISOString());
  return {
    label,
    lat: sample.lat,
    long: sample.long,
    date: sample.date.toISOString(),
    ...weather,
  };
}

async function main() {
  const args = parseArguments(process.argv.slice(2));
  const rng = createRng(args.seed);
  const rawRows = loadCsv(args.csv);
  const positiveCandidates = rawRows
    .map((row) => {
      const date = parseDateValue(row.date);
      const lat = parseNumber(row.lat);
      const long = parseNumber(row.long);
      if (!date || lat === null || long === null) {
        return null;
      }

      return { date, lat, long };
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
  const negatives = [];
  let attempts = 0;

  while (negatives.length < args.negatives && attempts < args.maxAttempts) {
    attempts += 1;
    const anchor = positiveCandidates[Math.floor(rng() * positiveCandidates.length)];
    const candidate = generateNegativeCandidate(anchor, bounds, rng);
    if (isFarFromPositives(candidate, positiveIndex, args.timeBufferDays, args.minDistanceKm)) {
      negatives.push(candidate);
    }
  }

  if (negatives.length < args.negatives) {
    throw new Error(`Only generated ${negatives.length} negatives after ${args.maxAttempts} attempts.`);
  }

  const samples = [];

  for (const positive of selectedPositives) {
    samples.push(await enrichSample(positive, 1));
  }

  for (const negative of negatives) {
    samples.push(await enrichSample(negative, 0));
  }

  samples.sort((left, right) => new Date(left.date) - new Date(right.date));

  const document = {
    datasetType: "historical_fire_vs_background",
    createdAt: new Date().toISOString(),
    sourceCsv: path.resolve(args.csv),
    generationParameters: {
      positives: args.positives,
      negatives: args.negatives,
      minDistanceKm: args.minDistanceKm,
      timeBufferDays: args.timeBufferDays,
      seed: args.seed,
    },
    samples,
  };

  saveJson(args.output, document);
  console.log(`Saved dataset to ${path.resolve(args.output)}`);
  console.log(`Positive samples: ${selectedPositives.length}`);
  console.log(`Negative samples: ${negatives.length}`);
}

main().catch((error) => {
  console.error(error.message);
  process.exitCode = 1;
});
