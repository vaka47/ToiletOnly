#!/usr/bin/env python3

import argparse
import base64
import csv
import json
import os
import statistics
import urllib.error
import urllib.request
from pathlib import Path


PUBLIC_MODELS = {
    "candidate_b": {"slug": "toilet-ydj8f-e8yca", "version": 1},
    "candidate_c": {"slug": "toilet-ydj8f-adpoa", "version": 1},
}


def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument("--images-dir", required=True)
    p.add_argument("--local-weights", required=True)
    p.add_argument("--output-csv", required=True)
    p.add_argument("--output-md", required=True)
    p.add_argument("--imgsz", type=int, default=448)
    return p.parse_args()


def infer_local(weights_path: str, images, imgsz: int):
    from ultralytics import YOLO

    model = YOLO(weights_path)
    results = {}
    for image_path in images:
        preds = model.predict(
            source=str(image_path),
            imgsz=imgsz,
            conf=0.001,
            iou=0.7,
            device="cpu",
            verbose=False,
            save=False,
            save_txt=False,
            save_conf=False,
            show=False,
        )
        result = preds[0]
        confs = []
        if getattr(result, "boxes", None) is not None and result.boxes.conf is not None:
            confs = [float(v) for v in result.boxes.conf.tolist()]
        results[image_path.name] = max(confs) * 100 if confs else 0.0
    return results


def infer_public(model_slug: str, version: int, api_key: str, images):
    results = {}
    url = f"https://detect.roboflow.com/{model_slug}/{version}?api_key={api_key}&confidence=1&overlap=30"

    for image_path in images:
        payload = base64.b64encode(image_path.read_bytes())
        req = urllib.request.Request(
            url,
            data=payload,
            headers={"Content-Type": "application/x-www-form-urlencoded"},
        )
        try:
            with urllib.request.urlopen(req, timeout=90) as resp:
                body = json.loads(resp.read().decode("utf-8"))
        except urllib.error.HTTPError as exc:
            error_body = exc.read().decode("utf-8", "ignore")
            raise RuntimeError(f"{model_slug} failed on {image_path.name}: HTTP {exc.code} {error_body}") from exc

        preds = body.get("predictions", [])
        confs = [float(p.get("confidence", 0.0)) for p in preds]
        results[image_path.name] = max(confs) * 100 if confs else 0.0
    return results


def expected_from_name(name: str):
    return "detect" if name.startswith("T") else "ignore"


def scene_label(name: str):
    stem = Path(name).stem
    return stem.split("_", 1)[1] if "_" in stem else stem


def summarize(rows, key):
    detect = [r[key] for r in rows if r["expected"] == "detect"]
    ignore = [r[key] for r in rows if r["expected"] == "ignore"]
    return {
        "detect_mean": statistics.mean(detect) if detect else 0.0,
        "ignore_mean": statistics.mean(ignore) if ignore else 0.0,
        "detect_min": min(detect) if detect else 0.0,
        "ignore_max": max(ignore) if ignore else 0.0,
    }


def main():
    args = parse_args()
    api_key = os.environ.get("ROBOFLOW_API_KEY", "").strip()
    if not api_key:
        raise SystemExit("ROBOFLOW_API_KEY is required in the environment")

    images_dir = Path(args.images_dir)
    images = sorted(p for p in images_dir.iterdir() if p.is_file())

    local_scores = infer_local(args.local_weights, images, args.imgsz)
    public_scores = {}
    for name, spec in PUBLIC_MODELS.items():
        public_scores[name] = infer_public(spec["slug"], spec["version"], api_key, images)

    rows = []
    for image_path in images:
        rows.append(
            {
                "scene_id": image_path.stem.split("_", 1)[0],
                "file": image_path.name,
                "scene": scene_label(image_path.name),
                "expected": expected_from_name(image_path.name),
                "local_v6_confidence": round(local_scores[image_path.name], 1),
                "candidate_b_confidence": round(public_scores["candidate_b"][image_path.name], 1),
                "candidate_c_confidence": round(public_scores["candidate_c"][image_path.name], 1),
            }
        )

    output_csv = Path(args.output_csv)
    output_csv.parent.mkdir(parents=True, exist_ok=True)
    with output_csv.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(
            f,
            fieldnames=[
                "scene_id",
                "file",
                "scene",
                "expected",
                "local_v6_confidence",
                "candidate_b_confidence",
                "candidate_c_confidence",
            ],
        )
        writer.writeheader()
        writer.writerows(rows)

    local_summary = summarize(rows, "local_v6_confidence")
    b_summary = summarize(rows, "candidate_b_confidence")
    c_summary = summarize(rows, "candidate_c_confidence")

    md = Path(args.output_md)
    md.parent.mkdir(parents=True, exist_ok=True)
    with md.open("w", encoding="utf-8") as f:
        f.write("# A/B Test Results\n\n")
        f.write(f"- Images: `{images_dir}`\n")
        f.write(f"- Local weights: `{args.local_weights}`\n\n")
        f.write("## Summary\n\n")
        for label, summary in [
            ("local_v6", local_summary),
            ("candidate_b", b_summary),
            ("candidate_c", c_summary),
        ]:
            f.write(f"### {label}\n\n")
            f.write(f"- detect mean confidence: `{summary['detect_mean']:.1f}`\n")
            f.write(f"- ignore mean confidence: `{summary['ignore_mean']:.1f}`\n")
            f.write(f"- detect min confidence: `{summary['detect_min']:.1f}`\n")
            f.write(f"- ignore max confidence: `{summary['ignore_max']:.1f}`\n\n")

        f.write("## Per Image\n\n")
        f.write("| scene_id | expected | file | local_v6 | candidate_b | candidate_c |\n")
        f.write("|---|---|---|---:|---:|---:|\n")
        for row in rows:
            f.write(
                f"| {row['scene_id']} | {row['expected']} | {row['file']} | "
                f"{row['local_v6_confidence']:.1f} | {row['candidate_b_confidence']:.1f} | "
                f"{row['candidate_c_confidence']:.1f} |\n"
            )

    print(f"Saved CSV to {output_csv}")
    print(f"Saved Markdown summary to {md}")


if __name__ == "__main__":
    main()
