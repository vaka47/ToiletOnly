#!/usr/bin/env bash
set -euo pipefail

# Objects365 is non-commercial only. Do NOT use for commercial apps.
# Provide URLs in a text file (one per line).

URLS_FILE="${1:-/Users/vaka47/Dev/Приложение в туалете/ml/data/objects365_urls.txt}"
OUT_DIR="${2:-/Users/vaka47/Dev/Приложение в туалете/ml/data/objects365}"

mkdir -p "${OUT_DIR}"

if [[ ! -f "${URLS_FILE}" ]]; then
  echo "Missing ${URLS_FILE}. Put direct download URLs or a .torrent URL (one per line)."
  exit 1
fi

while IFS= read -r url; do
  [[ -z "${url}" ]] && continue
  filename=$(basename "${url}")
  echo "Downloading ${filename}..."
  if command -v aria2c >/dev/null 2>&1; then
    aria2c -x 8 -s 8 -d "${OUT_DIR}" "${url}"
  else
    curl -L "${url}" -o "${OUT_DIR}/${filename}"
  fi
  echo "Saved ${filename} to ${OUT_DIR}"
done < "${URLS_FILE}"

cat <<'NOTE'
NOTE:
- Objects365 is non-commercial only.
- The dataset is huge (hundreds of GB). Ensure enough disk space.
NOTE
