#!/usr/bin/env python3
import argparse
import csv
from pathlib import Path


NEGATIVE_LABELS = {
    "chair",
    "couch",
    "bed",
    "dining table",
    "sink",
    "refrigerator",
    "microwave",
    "oven",
    "tv",
    "laptop",
}


def parse_args():
    parser = argparse.ArgumentParser(description="Regression test for ToiletOnly custom detector + COCO scene guard.")
    parser.add_argument("--images-dir", required=True)
    parser.add_argument("--toilet-weights", required=True)
    parser.add_argument("--scene-weights", required=True)
    parser.add_argument("--output-csv", required=True)
    parser.add_argument("--imgsz", type=int, default=448)
    parser.add_argument("--custom-threshold", type=float, default=0.42)
    parser.add_argument("--unlock-threshold", type=float, default=0.55)
    parser.add_argument("--guard-threshold", type=float, default=0.48)
    parser.add_argument("--scene-toilet-threshold", type=float, default=0.24)
    parser.add_argument("--very-high-custom-threshold", type=float, default=0.88)
    return parser.parse_args()


def expected_from_name(name: str) -> str:
    return "detect" if name.startswith("T") else "ignore"


def max_toilet_conf(model, image_path: Path, imgsz: int) -> float:
    result = model.predict(
        source=str(image_path),
        imgsz=imgsz,
        conf=0.001,
        iou=0.7,
        device="cpu",
        verbose=False,
        save=False,
        show=False,
    )[0]
    if result.boxes is None or result.boxes.conf is None:
        return 0.0
    confs = [float(v) for v in result.boxes.conf.tolist()]
    return max(confs) if confs else 0.0


def scene_guard(model, image_path: Path, imgsz: int):
    result = model.predict(
        source=str(image_path),
        imgsz=imgsz,
        conf=0.001,
        iou=0.7,
        device="cpu",
        verbose=False,
        save=False,
        show=False,
    )[0]
    names = result.names
    top_label = "none"
    top_conf = 0.0
    toilet_conf = 0.0
    negative_label = "none"
    negative_conf = 0.0

    if result.boxes is None or result.boxes.conf is None or result.boxes.cls is None:
        return top_label, top_conf, toilet_conf, negative_label, negative_conf

    for cls, conf in zip(result.boxes.cls.tolist(), result.boxes.conf.tolist()):
        label = str(names[int(cls)]).lower()
        conf = float(conf)
        if conf > top_conf:
            top_conf = conf
            top_label = label
        if label == "toilet":
            toilet_conf = max(toilet_conf, conf)
        if label in NEGATIVE_LABELS and conf > negative_conf:
            negative_conf = conf
            negative_label = label

    return top_label, top_conf, toilet_conf, negative_label, negative_conf


def decision(custom_conf, scene_toilet_conf, negative_label, negative_conf, args):
    has_scene_toilet = scene_toilet_conf >= args.scene_toilet_threshold
    has_very_high_custom_toilet = custom_conf >= args.very_high_custom_threshold
    scene_blocks = negative_conf >= args.guard_threshold and negative_conf >= scene_toilet_conf + 0.12
    semantic_mismatch_blocks = (
        custom_conf >= 0.55
        and not has_scene_toilet
        and not has_very_high_custom_toilet
    )
    blocked = scene_blocks or semantic_mismatch_blocks
    evidence = max(custom_conf, min(1.0, custom_conf * 0.70 + scene_toilet_conf * 0.42))
    unlock_score = evidence * 0.96
    has_toilet_evidence = has_scene_toilet or has_very_high_custom_toilet
    detected = (
        not blocked
        and custom_conf >= args.custom_threshold
        and has_toilet_evidence
        and unlock_score >= args.unlock_threshold
    )
    if detected:
        return "detect", unlock_score, "confirmed"
    if scene_blocks:
        return "ignore", unlock_score, f"blocked:{negative_label}"
    if semantic_mismatch_blocks:
        return "ignore", unlock_score, "blocked:lookalike"
    if not has_toilet_evidence:
        return "ignore", unlock_score, "scene_no_toilet"
    return "ignore", unlock_score, "weak_toilet_evidence"


def main():
    args = parse_args()
    from ultralytics import YOLO

    images = sorted(
        p for p in Path(args.images_dir).iterdir()
        if p.suffix.lower() in {".jpg", ".jpeg", ".png", ".webp"}
    )
    toilet_model = YOLO(args.toilet_weights)
    scene_model = YOLO(args.scene_weights)

    rows = []
    for image_path in images:
        custom_conf = max_toilet_conf(toilet_model, image_path, args.imgsz)
        top_label, top_conf, scene_toilet_conf, negative_label, negative_conf = scene_guard(
            scene_model, image_path, args.imgsz
        )
        predicted, unlock_score, reason = decision(
            custom_conf,
            scene_toilet_conf,
            negative_label,
            negative_conf,
            args,
        )
        expected = expected_from_name(image_path.name)
        rows.append(
            {
                "file": image_path.name,
                "expected": expected,
                "predicted": predicted,
                "pass": predicted == expected,
                "unlock_score": round(unlock_score * 100, 1),
                "custom_toilet": round(custom_conf * 100, 1),
                "scene_top": top_label,
                "scene_top_conf": round(top_conf * 100, 1),
                "scene_toilet": round(scene_toilet_conf * 100, 1),
                "negative": negative_label,
                "negative_conf": round(negative_conf * 100, 1),
                "reason": reason,
            }
        )

    output = Path(args.output_csv)
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)

    passed = sum(1 for row in rows if row["pass"])
    print(f"Saved {output}")
    print(f"Passed {passed}/{len(rows)}")
    for row in rows:
        status = "PASS" if row["pass"] else "FAIL"
        print(
            f"{status} {row['file']} expected={row['expected']} predicted={row['predicted']} "
            f"score={row['unlock_score']} custom={row['custom_toilet']} "
            f"scene_toilet={row['scene_toilet']} negative={row['negative']}:{row['negative_conf']} "
            f"reason={row['reason']}"
        )


if __name__ == "__main__":
    main()
