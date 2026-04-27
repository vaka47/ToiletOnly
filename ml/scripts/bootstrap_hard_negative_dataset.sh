#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

BASE_YOLO=""
OUT_DATASET=""
LISTS_OUT=""
YAML_OUT=""
WORK_DIR=""

OPENIMAGES_DIR="${ROOT_DIR}/data/openimages_hard_negatives"
OPENIMAGES_CLASS_FILE="${ROOT_DIR}/data/openimages_hard_negative_classes.txt"
SKIP_OPENIMAGES_DOWNLOAD=0

VIDEO_SRC=""
VIDEO_FRAMES_OUT=""
VIDEO_INTERVAL_SECONDS="2"

OBJECTS365_IMAGES_ROOT=""
OBJECTS365_ANNOTATIONS="${ROOT_DIR}/data/objects365/zhiyuan_objv2_val.json"
OBJECTS365_OUT=""
OBJECTS365_CLASS_FILE="${ROOT_DIR}/data/objects365_hard_negative_classes.txt"
OBJECTS365_LIMIT="0"

EXTRA_NEGATIVE_SRCS=()
EXTRA_BACKGROUND_YOLO_SRCS=()

usage() {
  echo "Usage:" >&2
  echo "  $0 --base-yolo <path> --out-dataset <path> --lists-out <path> --yaml-out <path> --work-dir <path> [options]" >&2
  echo >&2
  echo "Options:" >&2
  echo "  --skip-openimages-download           Reuse existing Open Images negatives instead of downloading." >&2
  echo "  --openimages-dir <path>              Output/input dir for Open Images hard negatives." >&2
  echo "  --openimages-class-file <path>       Open Images hard-negative class list." >&2
  echo "  --video-src <path>                   Directory with your negative videos." >&2
  echo "  --video-frames-out <path>            Output dir for extracted negative video frames." >&2
  echo "  --video-interval-seconds <n>         Extract one frame every N seconds. Default: 2." >&2
  echo "  --objects365-images-root <path>      Root dir with extracted Objects365 images." >&2
  echo "  --objects365-annotations <path>      Objects365 annotation JSON. Default: zhiyuan_objv2_val.json." >&2
  echo "  --objects365-out <path>              Output dir for Objects365 background YOLO dataset." >&2
  echo "  --objects365-class-file <path>       Objects365 hard-negative class list." >&2
  echo "  --objects365-limit <n>               Optional max copied images from Objects365. Default: 0." >&2
  echo "  --extra-negative-src <path>          Extra raw negative image dir. Repeatable." >&2
  echo "  --extra-background-yolo-src <path>   Extra YOLO background dataset dir. Repeatable." >&2
}

dir_has_files() {
  local path="$1"
  if [[ ! -d "${path}" ]]; then
    return 1
  fi

  find "${path}" -type f -print -quit | grep -q .
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --base-yolo)
      BASE_YOLO="$2"
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
    --skip-openimages-download)
      SKIP_OPENIMAGES_DOWNLOAD=1
      shift
      ;;
    --openimages-dir)
      OPENIMAGES_DIR="$2"
      shift 2
      ;;
    --openimages-class-file)
      OPENIMAGES_CLASS_FILE="$2"
      shift 2
      ;;
    --video-src)
      VIDEO_SRC="$2"
      shift 2
      ;;
    --video-frames-out)
      VIDEO_FRAMES_OUT="$2"
      shift 2
      ;;
    --video-interval-seconds)
      VIDEO_INTERVAL_SECONDS="$2"
      shift 2
      ;;
    --objects365-images-root)
      OBJECTS365_IMAGES_ROOT="$2"
      shift 2
      ;;
    --objects365-annotations)
      OBJECTS365_ANNOTATIONS="$2"
      shift 2
      ;;
    --objects365-out)
      OBJECTS365_OUT="$2"
      shift 2
      ;;
    --objects365-class-file)
      OBJECTS365_CLASS_FILE="$2"
      shift 2
      ;;
    --objects365-limit)
      OBJECTS365_LIMIT="$2"
      shift 2
      ;;
    --extra-negative-src)
      EXTRA_NEGATIVE_SRCS+=("$2")
      shift 2
      ;;
    --extra-background-yolo-src)
      EXTRA_BACKGROUND_YOLO_SRCS+=("$2")
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "${BASE_YOLO}" || -z "${OUT_DATASET}" || -z "${LISTS_OUT}" || -z "${YAML_OUT}" || -z "${WORK_DIR}" ]]; then
  usage
  exit 1
fi

mkdir -p "${WORK_DIR}"

NEGATIVE_SRCS=()
BACKGROUND_YOLO_SRCS=()

if [[ ${SKIP_OPENIMAGES_DOWNLOAD} -eq 0 ]]; then
  "${ROOT_DIR}/scripts/download_openimages_hard_negatives.sh" \
    "${OPENIMAGES_DIR}" \
    "${OPENIMAGES_CLASS_FILE}"
fi

if dir_has_files "${OPENIMAGES_DIR}"; then
  NEGATIVE_SRCS+=("${OPENIMAGES_DIR}")
fi

if [[ -n "${VIDEO_SRC}" ]]; then
  if [[ -z "${VIDEO_FRAMES_OUT}" ]]; then
    VIDEO_FRAMES_OUT="${WORK_DIR}/negatives_from_video"
  fi

  python3 "${ROOT_DIR}/scripts/extract_video_frames.py" \
    --src "${VIDEO_SRC}" \
    --out "${VIDEO_FRAMES_OUT}" \
    --every-seconds "${VIDEO_INTERVAL_SECONDS}"

  if dir_has_files "${VIDEO_FRAMES_OUT}"; then
    NEGATIVE_SRCS+=("${VIDEO_FRAMES_OUT}")
  fi
fi

if [[ -n "${OBJECTS365_IMAGES_ROOT}" ]]; then
  if [[ -z "${OBJECTS365_OUT}" ]]; then
    OBJECTS365_OUT="${WORK_DIR}/objects365_hard_negatives_yolo"
  fi
  OBJECTS365_SPLIT_OUT="${WORK_DIR}/objects365_hard_negatives_split_yolo"

  python3 "${ROOT_DIR}/scripts/build_objects365_background_yolo.py" \
    --annotations "${OBJECTS365_ANNOTATIONS}" \
    --images-root "${OBJECTS365_IMAGES_ROOT}" \
    --out "${OBJECTS365_OUT}" \
    --split train \
    --class-file "${OBJECTS365_CLASS_FILE}" \
    --limit "${OBJECTS365_LIMIT}"

  python3 "${ROOT_DIR}/scripts/build_background_yolo_dataset.py" \
    --src "${OBJECTS365_OUT}/images/train" \
    --out "${OBJECTS365_SPLIT_OUT}" \
    --prefix o365neg

  BACKGROUND_YOLO_SRCS+=("${OBJECTS365_SPLIT_OUT}")
fi

for path in "${EXTRA_NEGATIVE_SRCS[@]}"; do
  NEGATIVE_SRCS+=("${path}")
done

for path in "${EXTRA_BACKGROUND_YOLO_SRCS[@]}"; do
  BACKGROUND_YOLO_SRCS+=("${path}")
done

PREPARE_CMD=(
  "${ROOT_DIR}/scripts/prepare_hard_negative_dataset.sh"
  --base-yolo "${BASE_YOLO}"
  --out-dataset "${OUT_DATASET}"
  --lists-out "${LISTS_OUT}"
  --yaml-out "${YAML_OUT}"
  --work-dir "${WORK_DIR}"
)

for path in "${NEGATIVE_SRCS[@]}"; do
  PREPARE_CMD+=(--negative-src "${path}")
done

for path in "${BACKGROUND_YOLO_SRCS[@]}"; do
  PREPARE_CMD+=(--background-yolo-src "${path}")
done

"${PREPARE_CMD[@]}"
