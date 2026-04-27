#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DATA_DIR="${1:-${ROOT_DIR}/data/openimages_hard_negatives}"
CLASS_FILE="${2:-${ROOT_DIR}/data/openimages_hard_negative_classes.txt}"

LIMIT_TRAIN_PER_CLASS="${LIMIT_TRAIN_PER_CLASS:-60}"
LIMIT_VAL_PER_CLASS="${LIMIT_VAL_PER_CLASS:-15}"
LIMIT_TEST_PER_CLASS="${LIMIT_TEST_PER_CLASS:-15}"

if [[ ! -f "${CLASS_FILE}" ]]; then
  echo "Class file not found: ${CLASS_FILE}" >&2
  exit 1
fi

python3 -m pip install --upgrade --quiet oidv6

while IFS= read -r klass; do
  [[ -z "${klass}" ]] && continue
  [[ "${klass}" =~ ^# ]] && continue

  echo "Downloading Open Images hard negatives for class: ${klass}"

  oidv6 downloader \
    --dataset "${DATA_DIR}" \
    --type_data "train" \
    --classes "${klass}" \
    --limit "${LIMIT_TRAIN_PER_CLASS}" \
    --yes

  oidv6 downloader \
    --dataset "${DATA_DIR}" \
    --type_data "validation" \
    --classes "${klass}" \
    --limit "${LIMIT_VAL_PER_CLASS}" \
    --yes

  oidv6 downloader \
    --dataset "${DATA_DIR}" \
    --type_data "test" \
    --classes "${klass}" \
    --limit "${LIMIT_TEST_PER_CLASS}" \
    --yes
done < "${CLASS_FILE}"

cat <<NOTE
Downloaded Open Images hard-negative packs into:
  ${DATA_DIR}

Next step:
  1) Build a background-only YOLO dataset with empty labels.
  2) Exclude any Open Images images that also contain Toilet.
  3) Merge that background dataset into your toilet dataset.
NOTE
