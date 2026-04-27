#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

export YOLO_CONFIG_DIR="${YOLO_CONFIG_DIR:-$ROOT_DIR/ultralytics}"
export MPLCONFIGDIR="${MPLCONFIGDIR:-$ROOT_DIR/.matplotlib}"

DATA_PATH=""
MODEL_PATH=""
EPOCHS=""
IMGSZ="640"
BATCH="16"
RUN_NAME=""
DEVICE="cpu"
SLEEP_ON_FAIL="5"

usage() {
  cat <<'USAGE'
Usage: ml/scripts/train_resume.sh --data <yaml> --model <weights> --epochs <n> --name <run_name> [options]

Options:
  --imgsz <n>        Image size (default: 640)
  --batch <n>        Batch size (default: 16)
  --device <d>       Device (default: cpu)
  --sleep <sec>      Sleep between retries (default: 5)

Example:
  ml/scripts/train_resume.sh \
    --data ml/data/toilet.yaml \
    --model ml/runs/detect/toilet_yolov8n_ft_805_continue_2/weights/last.pt \
    --epochs 45 \
    --name toilet_yolov8n_ft_805_continue_2 \
    --device cpu
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --data)
      DATA_PATH="$2"
      shift 2
      ;;
    --model)
      MODEL_PATH="$2"
      shift 2
      ;;
    --epochs)
      EPOCHS="$2"
      shift 2
      ;;
    --imgsz)
      IMGSZ="$2"
      shift 2
      ;;
    --batch)
      BATCH="$2"
      shift 2
      ;;
    --name)
      RUN_NAME="$2"
      shift 2
      ;;
    --device)
      DEVICE="$2"
      shift 2
      ;;
    --sleep)
      SLEEP_ON_FAIL="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown аргумент: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$DATA_PATH" || -z "$MODEL_PATH" || -z "$EPOCHS" || -z "$RUN_NAME" ]]; then
  usage
  exit 1
fi

echo "Starting resumable training:"
echo "  data:  $DATA_PATH"
echo "  model: $MODEL_PATH"
echo "  epochs: $EPOCHS"
echo "  name:  $RUN_NAME"

while true; do
  python3 "$ROOT_DIR/scripts/train.py" \
    --data "$DATA_PATH" \
    --model "$MODEL_PATH" \
    --epochs "$EPOCHS" \
    --imgsz "$IMGSZ" \
    --batch "$BATCH" \
    --name "$RUN_NAME" \
    --device "$DEVICE" \
    --resume && break

  echo "Training crashed. Restarting in ${SLEEP_ON_FAIL}s..."
  sleep "$SLEEP_ON_FAIL"
done

echo "Training finished."
