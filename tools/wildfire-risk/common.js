"use strict";

const fs = require("fs");
const path = require("path");

const FEATURE_SPECS = [
  { name: "lat", source: "lat" },
  { name: "long", source: "long" },
  { name: "groundHeatFlux", source: "Ground_Heat_Flux_surface" },
  { name: "canopyWater", source: "Plant_Canopy_Surface_Water_surface" },
  { name: "temperatureSurface", source: "Temperature_surface" },
  { name: "vegetationType", source: "Vegetation_Type_surface" },
  { name: "vegetation", source: "Vegetation_surface" },
  { name: "pdsi", source: "pdsi" },
  { name: "precipitation", source: "precipitation" },
  { name: "tmax", source: "tmax" },
  { name: "tmin", source: "tmin" },
  { name: "windU", source: "u-component_of_wind_hybrid" },
  { name: "windV", source: "v-component_of_wind_hybrid" },
];

const DERIVED_FEATURES = [
  "windSpeed",
  "dayOfYearSin",
  "dayOfYearCos",
];

const FEATURE_NAMES = FEATURE_SPECS.map((spec) => spec.name).concat(DERIVED_FEATURES);

function parseCsv(text) {
  const rows = [];
  let field = "";
  let row = [];
  let inQuotes = false;

  for (let index = 0; index < text.length; index += 1) {
    const char = text[index];

    if (char === "\"") {
      if (inQuotes && text[index + 1] === "\"") {
        field += "\"";
        index += 1;
      } else {
        inQuotes = !inQuotes;
      }
      continue;
    }

    if (char === "," && !inQuotes) {
      row.push(field);
      field = "";
      continue;
    }

    if ((char === "\n" || char === "\r") && !inQuotes) {
      if (char === "\r" && text[index + 1] === "\n") {
        index += 1;
      }

      row.push(field);
      field = "";

      if (row.length > 1 || row[0] !== "") {
        rows.push(row);
      }

      row = [];
      continue;
    }

    field += char;
  }

  if (field.length > 0 || row.length > 0) {
    row.push(field);
    rows.push(row);
  }

  if (rows.length === 0) {
    return [];
  }

  const headers = rows[0];
  return rows.slice(1).map((cells) => {
    const record = {};
    headers.forEach((header, headerIndex) => {
      record[header] = cells[headerIndex] ?? "";
    });
    return record;
  });
}

function loadCsv(csvPath) {
  const absolutePath = path.resolve(csvPath);
  const text = fs.readFileSync(absolutePath, "utf8");
  return parseCsv(text);
}

function parseNumber(value) {
  if (value === undefined || value === null || value === "") {
    return null;
  }

  const numericValue = Number(value);
  return Number.isFinite(numericValue) ? numericValue : null;
}

function parseDateValue(value) {
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

function dayOfYear(date) {
  const start = new Date(Date.UTC(date.getUTCFullYear(), 0, 0));
  const diff = date - start;
  return Math.floor(diff / 86400000);
}

function buildFeatureMap(record, fallbackDate) {
  const featureMap = {};

  FEATURE_SPECS.forEach((spec) => {
    featureMap[spec.name] = parseNumber(record[spec.source]);
  });

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

function confidenceToTarget(confidenceValue, threshold = 80) {
  const numericConfidence = parseNumber(confidenceValue);
  return numericConfidence !== null && numericConfidence >= threshold ? 1 : 0;
}

function splitTemporal(records, ratio = 0.8) {
  const sorted = [...records].sort((left, right) => left.timestamp - right.timestamp);
  const splitIndex = Math.max(1, Math.min(sorted.length - 1, Math.floor(sorted.length * ratio)));
  return {
    training: sorted.slice(0, splitIndex),
    validation: sorted.slice(splitIndex),
  };
}

function computeImputationStats(records) {
  const sums = Object.fromEntries(FEATURE_NAMES.map((name) => [name, 0]));
  const counts = Object.fromEntries(FEATURE_NAMES.map((name) => [name, 0]));

  for (const record of records) {
    for (const featureName of FEATURE_NAMES) {
      const value = record.features[featureName];
      if (value !== null && Number.isFinite(value)) {
        sums[featureName] += value;
        counts[featureName] += 1;
      }
    }
  }

  const means = {};
  FEATURE_NAMES.forEach((featureName) => {
    means[featureName] = counts[featureName] > 0 ? sums[featureName] / counts[featureName] : 0;
  });

  return means;
}

function applyImputation(records, means) {
  for (const record of records) {
    const missing = [];
    for (const featureName of FEATURE_NAMES) {
      if (record.features[featureName] === null || !Number.isFinite(record.features[featureName])) {
        record.features[featureName] = means[featureName];
        missing.push(featureName);
      }
    }
    record.missingFeatures = missing;
  }
}

function computeNormalizationStats(records) {
  const means = {};
  const stds = {};

  FEATURE_NAMES.forEach((featureName) => {
    const values = records.map((record) => record.features[featureName]);
    const mean = values.reduce((sum, value) => sum + value, 0) / values.length;
    const variance = values.reduce((sum, value) => sum + ((value - mean) ** 2), 0) / values.length;
    means[featureName] = mean;
    stds[featureName] = variance > 0 ? Math.sqrt(variance) : 1;
  });

  return { means, stds };
}

function normalizeVector(featureMap, stats) {
  return FEATURE_NAMES.map((featureName) => {
    const centered = featureMap[featureName] - stats.means[featureName];
    return centered / stats.stds[featureName];
  });
}

function imputeFeatureMap(featureMap, means) {
  const completedFeatureMap = { ...featureMap };
  const missingFeatures = [];

  FEATURE_NAMES.forEach((featureName) => {
    if (completedFeatureMap[featureName] === null || Number.isNaN(completedFeatureMap[featureName])) {
      completedFeatureMap[featureName] = means[featureName];
      missingFeatures.push(featureName);
    }
  });

  return {
    completedFeatureMap,
    missingFeatures,
  };
}

function sigmoid(value) {
  if (value >= 0) {
    const expValue = Math.exp(-value);
    return 1 / (1 + expValue);
  }

  const expValue = Math.exp(value);
  return expValue / (1 + expValue);
}

function dotProduct(left, right) {
  let total = 0;
  for (let index = 0; index < left.length; index += 1) {
    total += left[index] * right[index];
  }
  return total;
}

function trainLogisticRegression(records, options = {}) {
  const epochs = options.epochs ?? 600;
  const learningRate = options.learningRate ?? 0.05;
  const l2Penalty = options.l2Penalty ?? 0.001;
  const weights = new Array(FEATURE_NAMES.length).fill(0);
  let bias = 0;

  for (let epoch = 0; epoch < epochs; epoch += 1) {
    let biasGradient = 0;
    const weightGradients = new Array(weights.length).fill(0);

    for (const record of records) {
      const predicted = sigmoid(dotProduct(weights, record.vector) + bias);
      const error = predicted - record.target;
      biasGradient += error;

      for (let index = 0; index < weights.length; index += 1) {
        weightGradients[index] += error * record.vector[index];
      }
    }

    const scale = 1 / records.length;
    bias -= learningRate * biasGradient * scale;

    for (let index = 0; index < weights.length; index += 1) {
      const regularizedGradient = (weightGradients[index] * scale) + (l2Penalty * weights[index]);
      weights[index] -= learningRate * regularizedGradient;
    }
  }

  return { weights, bias };
}

function predictProbability(vector, model) {
  return sigmoid(dotProduct(model.weights, vector) + model.bias);
}

function confusionMetrics(scoredRecords, threshold = 0.5) {
  let truePositive = 0;
  let falsePositive = 0;
  let trueNegative = 0;
  let falseNegative = 0;

  for (const record of scoredRecords) {
    const predictedPositive = record.probability >= threshold;
    if (predictedPositive && record.target === 1) {
      truePositive += 1;
    } else if (predictedPositive && record.target === 0) {
      falsePositive += 1;
    } else if (!predictedPositive && record.target === 0) {
      trueNegative += 1;
    } else {
      falseNegative += 1;
    }
  }

  const total = scoredRecords.length;
  const accuracy = total > 0 ? (truePositive + trueNegative) / total : 0;
  const precision = (truePositive + falsePositive) > 0 ? truePositive / (truePositive + falsePositive) : 0;
  const recall = (truePositive + falseNegative) > 0 ? truePositive / (truePositive + falseNegative) : 0;

  return {
    threshold,
    truePositive,
    falsePositive,
    trueNegative,
    falseNegative,
    accuracy,
    precision,
    recall,
  };
}

function logLoss(scoredRecords) {
  const epsilon = 1e-9;
  const total = scoredRecords.reduce((sum, record) => {
    const probability = Math.min(1 - epsilon, Math.max(epsilon, record.probability));
    return sum - ((record.target * Math.log(probability)) + ((1 - record.target) * Math.log(1 - probability)));
  }, 0);
  return scoredRecords.length > 0 ? total / scoredRecords.length : 0;
}

function areaUnderCurve(scoredRecords) {
  const sorted = [...scoredRecords].sort((left, right) => right.probability - left.probability);
  const positives = sorted.filter((record) => record.target === 1).length;
  const negatives = sorted.length - positives;

  if (positives === 0 || negatives === 0) {
    return 0.5;
  }

  let truePositiveRate = 0;
  let falsePositiveRate = 0;
  let previousTruePositiveRate = 0;
  let previousFalsePositiveRate = 0;
  let auc = 0;

  for (const record of sorted) {
    if (record.target === 1) {
      truePositiveRate += 1 / positives;
    } else {
      falsePositiveRate += 1 / negatives;
    }

    auc += (falsePositiveRate - previousFalsePositiveRate) * ((truePositiveRate + previousTruePositiveRate) / 2);
    previousTruePositiveRate = truePositiveRate;
    previousFalsePositiveRate = falsePositiveRate;
  }

  return auc;
}

function ensureDirectoryExists(directoryPath) {
  fs.mkdirSync(directoryPath, { recursive: true });
}

function saveJson(filePath, value) {
  ensureDirectoryExists(path.dirname(filePath));
  fs.writeFileSync(filePath, `${JSON.stringify(value, null, 2)}\n`, "utf8");
}

function loadJson(filePath) {
  return JSON.parse(fs.readFileSync(path.resolve(filePath), "utf8"));
}

module.exports = {
  FEATURE_NAMES,
  FEATURE_SPECS,
  areaUnderCurve,
  applyImputation,
  buildFeatureMap,
  computeImputationStats,
  computeNormalizationStats,
  confidenceToTarget,
  confusionMetrics,
  ensureDirectoryExists,
  imputeFeatureMap,
  loadCsv,
  loadJson,
  logLoss,
  normalizeVector,
  parseDateValue,
  parseNumber,
  predictProbability,
  saveJson,
  splitTemporal,
  trainLogisticRegression,
};
