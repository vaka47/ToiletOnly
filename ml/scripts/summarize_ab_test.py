#!/usr/bin/env python3

import csv
from pathlib import Path


MODELS = {
    "local_v6": ("local_v6_confidence", "local_v6_opens"),
    "candidate_b": ("candidate_b_confidence", "candidate_b_opens"),
    "candidate_c": ("candidate_c_confidence", "candidate_c_opens"),
}


def parse_bool(value: str):
    value = (value or "").strip().lower()
    if value in {"1", "true", "yes", "y"}:
        return True
    if value in {"0", "false", "no", "n"}:
        return False
    return None


def parse_float(value: str):
    value = (value or "").strip().replace("%", "")
    if not value:
        return None
    try:
        return float(value)
    except ValueError:
        return None


def summarize(rows, label):
    detect_rows = [r for r in rows if r["expected"].strip() == "detect"]
    ignore_rows = [r for r in rows if r["expected"].strip() == "ignore"]

    print(f"\n== {label} ==")

    for model, (conf_key, open_key) in MODELS.items():
        detect_conf = [parse_float(r[conf_key]) for r in detect_rows]
        ignore_conf = [parse_float(r[conf_key]) for r in ignore_rows]
        detect_open = [parse_bool(r[open_key]) for r in detect_rows]
        ignore_open = [parse_bool(r[open_key]) for r in ignore_rows]

        detect_conf = [v for v in detect_conf if v is not None]
        ignore_conf = [v for v in ignore_conf if v is not None]
        detect_open = [v for v in detect_open if v is not None]
        ignore_open = [v for v in ignore_open if v is not None]

        mean_detect = sum(detect_conf) / len(detect_conf) if detect_conf else None
        mean_ignore = sum(ignore_conf) / len(ignore_conf) if ignore_conf else None
        open_detect = sum(1 for v in detect_open if v) / len(detect_open) if detect_open else None
        open_ignore = sum(1 for v in ignore_open if v) / len(ignore_open) if ignore_open else None

        print(f"{model}:")
        print(f"  detect mean confidence: {mean_detect:.1f}" if mean_detect is not None else "  detect mean confidence: n/a")
        print(f"  ignore mean confidence: {mean_ignore:.1f}" if mean_ignore is not None else "  ignore mean confidence: n/a")
        print(f"  detect open rate: {open_detect:.2f}" if open_detect is not None else "  detect open rate: n/a")
        print(f"  ignore open rate: {open_ignore:.2f}" if open_ignore is not None else "  ignore open rate: n/a")


def main():
    csv_path = Path("ml/ab_test/toilet_model_ab_test_template.csv")
    if not csv_path.exists():
        raise SystemExit(f"CSV not found: {csv_path}")

    with csv_path.open(newline="", encoding="utf-8") as f:
        rows = list(csv.DictReader(f))

    summarize(rows, csv_path)


if __name__ == "__main__":
    main()
