#!/usr/bin/env bash
set -euo pipefail

echo "1) Downloading Open Images (class Toilet)"
"/Users/vaka47/Dev/Приложение в туалете/ml/scripts/download_openimages.sh" \
  "/Users/vaka47/Dev/Приложение в туалете/ml/data/openimages"

echo "2) Downloading Roboflow dataset (requires ROBOFLOW_API_KEY and args)"
python3 "/Users/vaka47/Dev/Приложение в туалете/ml/scripts/download_roboflow.py" \
  --workspace "YOUR_WORKSPACE" \
  --project "YOUR_PROJECT" \
  --version 1 \
  --out "/Users/vaka47/Dev/Приложение в туалете/ml/data/roboflow"

cat <<'NOTE'
NOTE:
- Update Roboflow args and provide ROBOFLOW_API_KEY.
- Conversion to YOLO is still required for Open Images.
- Objects365 is non-commercial and is not included here.
NOTE
