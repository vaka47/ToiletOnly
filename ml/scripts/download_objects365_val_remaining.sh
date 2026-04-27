#!/usr/bin/env bash
set -euo pipefail

# Download remaining Objects365 val patches (4..43) with resume support.
# Existing files are skipped.
#
# Usage:
#   ./download_objects365_val_remaining.sh [OUT_DIR] [PARALLEL]

OUT_DIR="${1:-/Volumes/Untitled/ToiletML/data/objects365_val}"
PARALLEL="${2:-4}"
BASE_URL="https://dorc.ks3-cn-beijing.ksyun.com/data-set/2020Objects365%E6%95%B0%E6%8D%AE%E9%9B%86/val"

mkdir -p "${OUT_DIR}"
TMP_LIST="$(mktemp)"

# Build URL list for missing patches only.
for i in $(seq 4 43); do
  if [[ "${i}" -le 15 ]]; then
    url="${BASE_URL}/images/v1/patch${i}.tar.gz"
  else
    url="${BASE_URL}/images/v2/patch${i}.tar.gz"
  fi
  file="${OUT_DIR}/patch${i}.tar.gz"
  if [[ ! -f "${file}" ]]; then
    echo "${url}" >> "${TMP_LIST}"
  fi
done

# Ensure val annotations are present.
if [[ ! -f "${OUT_DIR}/zhiyuan_objv2_val.json" ]]; then
  echo "${BASE_URL}/zhiyuan_objv2_val.json" >> "${TMP_LIST}"
fi

if [[ ! -s "${TMP_LIST}" ]]; then
  echo "All remaining files are already downloaded."
  rm -f "${TMP_LIST}"
  exit 0
fi

echo "Starting download to ${OUT_DIR} (parallel=${PARALLEL})"
echo "Planned URLs: $(wc -l < "${TMP_LIST}" | tr -d ' ')"

# Parallel download with retries + resume.
xargs -P "${PARALLEL}" -n 1 -I {} \
  sh -c 'url="$1"; out="$2/$(basename "$1")"; echo "Downloading $(basename "$1")"; curl -L --fail --retry 5 --retry-delay 3 -C - "$url" -o "$out"' _ {} "${OUT_DIR}" \
  < "${TMP_LIST}"

rm -f "${TMP_LIST}"
echo "Objects365 val remaining download complete."
