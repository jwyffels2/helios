import pandas as pd
import numpy as np
from sklearn.model_selection import train_test_split
from sklearn.ensemble import RandomForestClassifier
from sklearn.metrics import classification_report
from sklearn.calibration import CalibratedClassifierCV
import joblib
import folium

# =========================
# 1. LOAD DATA
# =========================

DATA_PATH = "data/firms_ee_join_clean.csv"

print("Loading dataset...")
df = pd.read_csv(DATA_PATH)

# =========================
# 2. PREPROCESS DATA
# =========================

print("Preprocessing data...")

# Drop time-based columns
columns_to_drop = [
    "date",
    "gridmet_time",
    "cpc_temp_time",
    "cpc_precip_time",
    "cfsr_time",
    "brightness",
    "frp",
    "confidence"
]

df = df.drop(columns=columns_to_drop, errors="ignore")

# Drop rows with missing values
df = df.dropna()

# Separate features and label
y = df["label"]
X = df.drop(columns=["label"])

# Save lat/long separately (not used for training)
lat_long = X[["lat", "long"]]

# Remove lat/long from training features
X = X.drop(columns=["lat", "long"])

# =========================
# 3. TRAIN MODEL
# =========================

print("Training model...")

X_train, X_test, y_train, y_test = train_test_split(
    X, y, test_size=0.2, random_state=42
)

model = RandomForestClassifier(
    n_estimators=100,
    class_weight="balanced",
    random_state=42
)

model = CalibratedClassifierCV(model, method="sigmoid")
model.fit(X_train, y_train)

# =========================
# 4. EVALUATE MODEL
# =========================

print("\nModel Evaluation:")
y_pred = model.predict(X_test)
print(classification_report(y_test, y_pred))

# =========================
# 5. SAVE MODEL
# =========================

MODEL_PATH = "output/wildfire_model.pkl"
joblib.dump(model, MODEL_PATH)

print(f"Model saved to {MODEL_PATH}")

# =========================
# 6. CREATE GRID (REGION)
# =========================

print("Creating geographic grid...")

# Temporary region
lat_range = np.arange(30, 40, 0.5)
lon_range = np.arange(-110, -95, 0.5)

grid_points = []

for lat in lat_range:
    for lon in lon_range:
        grid_points.append((lat, lon))

grid_df = pd.DataFrame(grid_points, columns=["lat", "long"])

# =========================
# 7. GENERATE FEATURE DATA FOR GRID
# =========================

print("Generating environmental data for grid...")

# NOTE: Replace with real-time API data later

sampled_rows = X.sample(n=len(grid_df), replace=True).reset_index(drop=True)

for col in X.columns:
    grid_df[col] = sampled_rows[col]

# =========================
# 8. PREDICT RISK
# =========================

print("Predicting wildfire risk...")

X_grid = grid_df[X.columns]

grid_df["risk"] = model.predict_proba(X_grid)[:, 1]

# =========================
# 9. FILTER HIGH-RISK AREAS
# =========================

RISK_THRESHOLD = 0.3

high_risk = grid_df[grid_df["risk"] > RISK_THRESHOLD]

print(f"High-risk locations found: {len(high_risk)}")

# =========================
# 10. VISUALIZE ON MAP
# =========================

print("Generating map...")

# Center map
center_lat = grid_df["lat"].mean()
center_lon = grid_df["long"].mean()

m = folium.Map(location=[center_lat, center_lon], zoom_start=5)

# Add high-risk points
for _, row in high_risk.iterrows():
    folium.CircleMarker(
        location=[row["lat"], row["long"]],
        radius=5,
        color="red",
        fill=True,
        fill_opacity=0.7,
        popup=f"Risk: {row['risk']:.2f}"
    ).add_to(m)

# Save map
MAP_PATH = "output/wildfire_map.html"
m.save(MAP_PATH)

print(f"Map saved to {MAP_PATH}")
