"use strict";

// Scores a CSV of coordinate requests with the true wildfire classifier.
// This is the batch demo path: it loads multiple locations, fetches or replays
// weather data for each row, ranks the results, and writes CSV/JSON outputs for
// presentation or downstream review.

const fs = require("fs");
const path = require("path");
const {
  loadCsv,
  loadJson,
  parseNumber,
  saveJson,
  writeCsv,
} = require("./common");
const {
  fetchOpenMeteoForecast,
  mapForecastPayloadToTrueClassifierInput,
} = require("./weather_api");
const {
  DEFAULT_CONTEXT_CSV,
  buildContextIndex,
  lookupNearestContext,
} = require("./context_lookup");
const {
  scoreTrueClassifierInput,
} = require("./true_classifier_runtime");

function parseArguments(argv) {
  // CLI options support both programmatic exports (JSON/CSV) and presentation
  // artifacts (text summary + globe HTML).
  const args = {
    model: path.join(__dirname, "output", "true_classifier_model.json"),
    input: null,
    outputJson: null,
    outputCsv: null,
    outputTxt: path.join(__dirname, "output", "potential_wildfires.txt"),
    outputHtml: path.join(__dirname, "output", "potential_wildfires_globe.html"),
    sourceFile: null,
    contextCsv: DEFAULT_CONTEXT_CSV,
    potentialThreshold: 0.5,
  };

  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];

    if (token === "--model") {
      args.model = argv[index + 1];
      index += 1;
    } else if (token === "--input") {
      args.input = argv[index + 1];
      index += 1;
    } else if (token === "--output-json") {
      args.outputJson = argv[index + 1];
      index += 1;
    } else if (token === "--output-csv") {
      args.outputCsv = argv[index + 1];
      index += 1;
    } else if (token === "--output-txt") {
      args.outputTxt = argv[index + 1];
      index += 1;
    } else if (token === "--output-html") {
      args.outputHtml = argv[index + 1];
      index += 1;
    } else if (token === "--source-file") {
      args.sourceFile = argv[index + 1];
      index += 1;
    } else if (token === "--context-csv") {
      args.contextCsv = argv[index + 1];
      index += 1;
    } else if (token === "--potential-threshold") {
      args.potentialThreshold = parseNumber(argv[index + 1]);
      index += 1;
    }
  }

  if (!args.input) {
    throw new Error("--input is required.");
  }
  if (!Number.isFinite(args.potentialThreshold) || args.potentialThreshold < 0 || args.potentialThreshold > 1) {
    throw new Error("--potential-threshold must be a number between 0 and 1.");
  }

  return args;
}

function normalizeBatchRow(row, index) {
  // Canonicalize lat/long/date/id fields from flexible CSV headers.
  const latitude = parseNumber(row.lat ?? row.latitude);
  const longitude = parseNumber(row.long ?? row.lon ?? row.longitude);

  if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) {
    throw new Error(`Row ${index + 1} is missing a valid lat/long pair.`);
  }

  return {
    id: row.id ?? row.name ?? `row-${index + 1}`,
    lat: latitude,
    long: longitude,
    date: row.date ?? null,
  };
}

async function loadWeatherPayload(args, latitude, longitude) {
  // Optional shared replay payload for offline runs; otherwise query live.
  if (args.sourceFile) {
    return loadJson(args.sourceFile);
  }

  return fetchOpenMeteoForecast(latitude, longitude);
}

async function scoreRow(row, args, model, contextIndex) {
  // Score one batch row end-to-end and keep diagnostics for traceability.
  // apiMappedInput is preserved in JSON output indirectly through featuresUsed
  // and missingFeatures so a reviewer can see what was actually scored.
  const weatherPayload = await loadWeatherPayload(args, row.lat, row.long);
  const apiMappedInput = mapForecastPayloadToTrueClassifierInput(
    weatherPayload,
    row.lat,
    row.long,
    row.date
  );
  Object.assign(apiMappedInput, lookupNearestContext(contextIndex, apiMappedInput));

  const {
    completedFeatureMap,
    missingFeatures,
    rawProbability,
    calibratedProbability,
  } = scoreTrueClassifierInput(apiMappedInput, model, new Date(apiMappedInput.date));

  return {
    id: row.id,
    lat: row.lat,
    long: row.long,
    date: apiMappedInput.date,
    rawProbability,
    wildfireProbability: calibratedProbability,
    missingFeatureCount: missingFeatures.length,
    missingFeatures,
    featuresUsed: completedFeatureMap,
  };
}

function printSummary(results) {
  // Terminal-friendly top-N summary for quick sanity checks.
  const topResults = results.slice(0, 10);
  topResults.forEach((result, index) => {
    console.log(
      `${index + 1}. ${result.id} (${result.lat}, ${result.long}) -> ${result.wildfireProbability.toFixed(4)}`
    );
  });
}

function selectPotentialWildfires(results, threshold) {
  return results.filter((result) => result.wildfireProbability >= threshold);
}

function printPotentialWildfireSummary(results, threshold) {
  // Print locations that cross the user-defined risk threshold.
  const potentialWildfires = selectPotentialWildfires(results, threshold);
  console.log(`Potential wildfire threshold: ${threshold.toFixed(2)}`);
  if (potentialWildfires.length === 0) {
    console.log("No potential wildfires exceeded the configured threshold.");
    return potentialWildfires;
  }

  potentialWildfires.forEach((result, index) => {
    console.log(
      `Potential ${index + 1}: (${result.lat.toFixed(6)}, ${result.long.toFixed(6)}) risk=${result.wildfireProbability.toFixed(4)} id=${result.id}`
    );
  });
  return potentialWildfires;
}

function writePotentialWildfiresText(outputPath, potentialWildfires, threshold) {
  // Persist a lightweight text report for sharing/logging.
  const absolutePath = path.resolve(outputPath);
  fs.mkdirSync(path.dirname(absolutePath), { recursive: true });

  const lines = [
    `Potential wildfire threshold: ${threshold.toFixed(2)}`,
    `Potential wildfire count: ${potentialWildfires.length}`,
    "",
  ];

  potentialWildfires.forEach((result, index) => {
    lines.push(
      `${index + 1}. lat=${result.lat.toFixed(6)}, long=${result.long.toFixed(6)}, risk=${result.wildfireProbability.toFixed(4)}, id=${result.id}, date=${result.date}`
    );
  });

  fs.writeFileSync(absolutePath, `${lines.join("\n")}\n`, "utf8");
  return absolutePath;
}

function escapeInlineJson(value) {
  // Prevent raw "<" characters from being interpreted as HTML/script tags.
  return JSON.stringify(value).replace(/</g, "\\u003c");
}

function writePotentialWildfiresGlobeHtml(outputPath, results, potentialWildfires, threshold) {
  // Write a self-contained Plotly globe page with risk-scaled markers.
  // If nothing exceeds the threshold, the page still shows the top ranked points
  // so the demo artifact remains useful for visual inspection.
  const absolutePath = path.resolve(outputPath);
  fs.mkdirSync(path.dirname(absolutePath), { recursive: true });

  const mapPoints = potentialWildfires.length > 0 ? potentialWildfires : results.slice(0, 200);
  const html = `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Potential Wildfires Globe</title>
  <script src="https://cdn.plot.ly/plotly-2.35.2.min.js"></script>
  <style>
    body { font-family: Arial, sans-serif; margin: 0; background: #0b1020; color: #f2f4f8; }
    .container { max-width: 1100px; margin: 0 auto; padding: 16px; }
    h1 { margin: 0 0 8px; font-size: 22px; }
    .meta { margin-bottom: 12px; color: #c8d1dc; }
    #globe { width: 100%; height: 76vh; min-height: 520px; }
  </style>
</head>
<body>
  <div class="container">
    <h1>Potential Wildfires Globe</h1>
    <div class="meta">
      Threshold: ${threshold.toFixed(2)} | Potential points: ${potentialWildfires.length} | Total scored: ${results.length}
    </div>
    <div id="globe"></div>
  </div>
  <script>
    const points = ${escapeInlineJson(mapPoints)};
    const trace = {
      type: "scattergeo",
      mode: "markers",
      lon: points.map((p) => p.long),
      lat: points.map((p) => p.lat),
      text: points.map((p) => \`\${p.id}: risk=\${Number(p.wildfireProbability).toFixed(4)}\`),
      hovertemplate: "%{text}<br>lat=%{lat:.4f}, long=%{lon:.4f}<extra></extra>",
      marker: {
        size: points.map((p) => 8 + (Number(p.wildfireProbability) * 14)),
        color: points.map((p) => Number(p.wildfireProbability)),
        cmin: 0,
        cmax: 1,
        colorscale: "YlOrRd",
        colorbar: { title: "Risk" },
        line: { color: "#f5f5f5", width: 0.6 }
      }
    };

    const layout = {
      paper_bgcolor: "#0b1020",
      plot_bgcolor: "#0b1020",
      font: { color: "#f2f4f8" },
      margin: { l: 10, r: 10, t: 10, b: 10 },
      geo: {
        projection: { type: "orthographic" },
        showland: true,
        landcolor: "#2a3b4d",
        showocean: true,
        oceancolor: "#0d1f3a",
        coastlinecolor: "#8ea1b6",
        showcountries: true,
        countrycolor: "#5f738a",
        bgcolor: "#0b1020"
      }
    };
    Plotly.newPlot("globe", [trace], layout, { responsive: true, displaylogo: false });
  </script>
</body>
</html>`;

  fs.writeFileSync(absolutePath, html, "utf8");
  return absolutePath;
}

async function main() {
  // Batch execution flow:
  // load rows -> score sequentially -> rank -> emit machine + human artifacts.
  const args = parseArguments(process.argv.slice(2));
  const model = loadJson(args.model);
  const contextIndex = buildContextIndex(args.contextCsv);
  const rows = loadCsv(args.input).map(normalizeBatchRow);
  const results = [];

  for (const row of rows) {
    // The loop is sequential on purpose. It avoids burst traffic to the weather
    // API and keeps terminal output/order easier to debug during demos.
    results.push(await scoreRow(row, args, model, contextIndex));
  }

  results.sort((left, right) => right.wildfireProbability - left.wildfireProbability);
  // Sorting happens before every export so CSV, JSON, terminal summary, and map
  // all agree on the same priority ordering.
  const potentialWildfires = selectPotentialWildfires(results, args.potentialThreshold);

  const outputDocument = {
    input: path.resolve(args.input),
    model: path.resolve(args.model),
    contextSource: contextIndex.csvPath,
    calibration: model.calibration ?? null,
    source: args.sourceFile
      ? {
          type: "file",
          path: path.resolve(args.sourceFile),
        }
      : {
          type: "open-meteo",
          url: "https://api.open-meteo.com/v1/forecast",
    },
    resultCount: results.length,
    potentialThreshold: args.potentialThreshold,
    potentialWildfireCount: potentialWildfires.length,
    results,
  };

  if (args.outputJson) {
    saveJson(args.outputJson, outputDocument);
  }

  if (args.outputCsv) {
    writeCsv(
      args.outputCsv,
      ["id", "lat", "long", "date", "rawProbability", "wildfireProbability", "missingFeatureCount"],
      results
    );
  }

  printSummary(results);
  const printedPotentialWildfires = printPotentialWildfireSummary(results, args.potentialThreshold);
  const textOutputPath = writePotentialWildfiresText(args.outputTxt, printedPotentialWildfires, args.potentialThreshold);
  const htmlOutputPath = writePotentialWildfiresGlobeHtml(
    args.outputHtml,
    results,
    printedPotentialWildfires,
    args.potentialThreshold
  );
  console.log(`Saved potential wildfire text report to ${textOutputPath}`);
  console.log(`Saved potential wildfire globe map to ${htmlOutputPath}`);
  if (!args.outputJson && !args.outputCsv) {
    console.log(JSON.stringify(outputDocument, null, 2));
  }
}

main().catch((error) => {
  console.error(error.message);
  process.exitCode = 1;
});
