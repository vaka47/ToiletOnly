#!/usr/bin/env bash
set -euo pipefail

# Downloads Open Images V6 data for class "Toilet" using oidv6.
# Requires: python3, pip

DATA_DIR="${1:-/Users/vaka47/Dev/Приложение в туалете/ml/data/openimages}"
# Limit per split to avoid huge downloads; override via env vars if needed.
LIMIT_TRAIN="${LIMIT_TRAIN:-2000}"
LIMIT_VAL="${LIMIT_VAL:-400}"
LIMIT_TEST="${LIMIT_TEST:-400}"

python3 -m pip install --upgrade --quiet oidv6

# Download train/val/test for the class "Toilet"
oidv6 downloader \
  --dataset "${DATA_DIR}" \
  --type_data "train" \
  --classes "Toilet" \
  --limit "${LIMIT_TRAIN}" \
  --yes
echo "Downloaded Open Images train to ${DATA_DIR} (limit=${LIMIT_TRAIN})"

oidv6 downloader \
  --dataset "${DATA_DIR}" \
  --type_data "validation" \
  --classes "Toilet" \
  --limit "${LIMIT_VAL}" \
  --yes
echo "Downloaded Open Images validation to ${DATA_DIR} (limit=${LIMIT_VAL})"

oidv6 downloader \
  --dataset "${DATA_DIR}" \
  --type_data "test" \
  --classes "Toilet" \
  --limit "${LIMIT_TEST}" \
  --yes
echo "Downloaded Open Images test to ${DATA_DIR} (limit=${LIMIT_TEST})"

cat <<'NOTE'
NOTE:
- Open Images downloads with labels in the oidv6 default format.
- You still need to convert to YOLO format before training with Ultralytics.
NOTE
