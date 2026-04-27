#!/usr/bin/env bash
set -euo pipefail

# Finalize big non-commercial dataset on external disk:
# 1) extract downloaded Objects365 val patches
# 2) build toilet-only YOLO subset from Objects365
# 3) merge base + full COCO + Objects365 into dataset_noncommercial_v4

O365_DIR="${1:-/Volumes/Untitled/ToiletML/data/objects365_val}"
O365_TOILET="${2:-/Volumes/Untitled/ToiletML/data/objects365_toilet_full}"
OUT_DATASET="${3:-/Volumes/Untitled/ToiletML/data/dataset_noncommercial_v4}"
BASE_DATASET="${4:-/Users/vaka47/Dev/Приложение в туалете/ml/data/dataset_aug}"
COCO_DATASET="${5:-/Volumes/Untitled/ToiletML/data/coco_toilet_full_clean}"

echo "[1/3] Extracting available patch*.tar.gz in ${O365_DIR}"
cd "${O365_DIR}"
for tarf in patch*.tar.gz; do
  [[ -f "${tarf}" ]] || continue
  echo "  extracting ${tarf}"
  tar -xzf "${tarf}"
done

echo "[2/3] Building Objects365 toilet YOLO subset"
python3 "/Users/vaka47/Dev/Приложение в туалете/ml/scripts/build_objects365_toilet_yolo.py" \
  --annotations "${O365_DIR}/zhiyuan_objv2_val.json" \
  --images-root "${O365_DIR}" \
  --out "${O365_TOILET}" \
  --split train

echo "[3/3] Merging datasets into ${OUT_DATASET}"
python3 "/Users/vaka47/Dev/Приложение в туалете/ml/scripts/merge_yolo_datasets.py" \
  --out "${OUT_DATASET}" \
  --source "base=${BASE_DATASET}" \
  --source "coco=${COCO_DATASET}" \
  --source "o365=${O365_TOILET}"

echo "Done. Dataset ready at: ${OUT_DATASET}"
