#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MERGE_IMAGE_MODE="${MERGE_IMAGE_MODE:-symlink}"

BASE_YOLO=""
OUT_DATASET=""
LISTS_OUT=""
YAML_OUT=""
WORK_DIR=""
NEGATIVE_SRCS=()
BACKGROUND_YOLO_SRCS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --base-yolo)
      BASE_YOLO="$2"
      shift 2
      ;;
    --negative-src)
      NEGATIVE_SRCS+=("$2")
      shift 2
      ;;
    --background-yolo-src)
      BACKGROUND_YOLO_SRCS+=("$2")
      shift 2
      ;;
    --out-dataset)
      OUT_DATASET="$2"
      shift 2
      ;;
    --lists-out)
      LISTS_OUT="$2"
      shift 2
      ;;
    --yaml-out)
      YAML_OUT="$2"
      shift 2
      ;;
    --work-dir)
      WORK_DIR="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "${BASE_YOLO}" || -z "${OUT_DATASET}" || -z "${LISTS_OUT}" || -z "${YAML_OUT}" || -z "${WORK_DIR}" ]]; then
  echo "Usage:" >&2
  echo "  $0 --base-yolo <path> [--negative-src <path> ...] [--background-yolo-src <path> ...] --out-dataset <path> --lists-out <path> --yaml-out <path> --work-dir <path>" >&2
  exit 1
fi

if [[ ${#NEGATIVE_SRCS[@]} -eq 0 && ${#BACKGROUND_YOLO_SRCS[@]} -eq 0 ]]; then
  echo "At least one --negative-src or --background-yolo-src is required" >&2
  exit 1
fi

TMP_BG_YOLO="${WORK_DIR}/background_negatives_yolo"
MERGE_SOURCES=("base=${BASE_YOLO}")

if [[ ${#NEGATIVE_SRCS[@]} -gt 0 ]]; then
  BUILD_BG_CMD=(
    python3 "${ROOT_DIR}/scripts/build_background_yolo_dataset.py"
    --out "${TMP_BG_YOLO}"
    --openimages-boxes-root "${ROOT_DIR}/data/openimages/boxes"
    --openimages-metadata "${ROOT_DIR}/data/openimages/metadata/class-descriptions-boxable.csv"
    --exclude-openimages-class Toilet
  )

  for src in "${NEGATIVE_SRCS[@]}"; do
    BUILD_BG_CMD+=(--src "${src}")
  done

  "${BUILD_BG_CMD[@]}"
  MERGE_SOURCES+=("neg=${TMP_BG_YOLO}")
fi

for i in "${!BACKGROUND_YOLO_SRCS[@]}"; do
  bg_src="${BACKGROUND_YOLO_SRCS[$i]}"
  MERGE_SOURCES+=("bg$((i + 1))=$(cd "${bg_src}" && pwd)")
done

MERGE_CMD=(
  python3 "${ROOT_DIR}/scripts/merge_yolo_datasets.py"
  --out "${OUT_DATASET}"
  --image-mode "${MERGE_IMAGE_MODE}"
)

for source in "${MERGE_SOURCES[@]}"; do
  MERGE_CMD+=(--source "${source}")
done

"${MERGE_CMD[@]}"

python3 "${ROOT_DIR}/scripts/generate_yolo_lists.py" \
  --dataset "${OUT_DATASET}" \
  --out-dir "${LISTS_OUT}" \
  --yaml-out "${YAML_OUT}" \
  --class-name toilet

NEGATIVE_SRCS_TEXT="none"
BACKGROUND_YOLO_SRCS_TEXT="none"

if [[ ${#NEGATIVE_SRCS[@]} -gt 0 ]]; then
  NEGATIVE_SRCS_TEXT="${NEGATIVE_SRCS[*]}"
fi

if [[ ${#BACKGROUND_YOLO_SRCS[@]} -gt 0 ]]; then
  BACKGROUND_YOLO_SRCS_TEXT="${BACKGROUND_YOLO_SRCS[*]}"
fi

cat <<NOTE
Hard-negative dataset prepared.
  base dataset:        ${BASE_YOLO}
  negative sources:    ${NEGATIVE_SRCS_TEXT}
  bg yolo sources:     ${BACKGROUND_YOLO_SRCS_TEXT}
  merge image mode:    ${MERGE_IMAGE_MODE}
  merged dataset:      ${OUT_DATASET}
  generated lists:     ${LISTS_OUT}
  generated yaml:      ${YAML_OUT}

Train with:
  yolo detect train model="/Users/vaka47/Dev/Приложение в туалете/yolov8n.pt" data="${YAML_OUT}" epochs=40 imgsz=448 batch=8 device=cpu workers=0 project="/Volumes/Untitled/ToiletML/runs" name=toilet_v6_hardneg
NOTE
