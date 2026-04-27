#!/usr/bin/env python3
from __future__ import annotations

import argparse
import csv
import random
import shutil
from pathlib import Path


IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".webp", ".bmp"}


def ensure_dir(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True)


def is_image(path: Path) -> bool:
    return path.is_file() and path.suffix.lower() in IMAGE_EXTENSIONS


def iter_input_images(path: Path):
    if path.is_file():
        if is_image(path):
            yield path
        return

    for candidate in sorted(path.rglob("*")):
        if is_image(candidate):
            yield candidate


def load_openimages_label_ids(metadata_path: Path, class_names: list[str]) -> set[str]:
    wanted = {name.strip().lower() for name in class_names if name.strip()}
    found: set[str] = set()
    found_names: set[str] = set()

    with metadata_path.open("r", newline="") as fh:
        reader = csv.reader(fh)
        for row in reader:
            if len(row) < 2:
                continue
            label_id, display_name = row[0].strip(), row[1].strip().lower()
            if display_name in wanted:
                found.add(label_id)
                found_names.add(display_name)

    missing = sorted(wanted - found_names)
    if missing:
        raise SystemExit(
            "Open Images classes not found in metadata: "
            + ", ".join(missing)
        )
    return found


def load_openimages_reject_ids(
    boxes_root: Path,
    metadata_path: Path,
    class_names: list[str],
) -> dict[str, set[str]]:
    label_ids = load_openimages_label_ids(metadata_path, class_names)
    split_files = {
        "train": boxes_root / "oidv6-train-annotations-bbox.csv",
        "validation": boxes_root / "validation-annotations-bbox.csv",
        "test": boxes_root / "test-annotations-bbox.csv",
    }
    reject_ids: dict[str, set[str]] = {key: set() for key in split_files}

    for split, csv_path in split_files.items():
        if not csv_path.exists():
            continue
        with csv_path.open("r", newline="") as fh:
            reader = csv.DictReader(fh)
            for row in reader:
                if row.get("LabelName") in label_ids:
                    image_id = (row.get("ImageID") or "").strip()
                    if image_id:
                        reject_ids[split].add(image_id)
    return reject_ids


def infer_openimages_split(path: Path) -> str | None:
    for part in path.parts:
        lowered = part.lower()
        if lowered == "train":
            return "train"
        if lowered == "validation":
            return "validation"
        if lowered == "test":
            return "test"
    return None


def should_skip_for_openimages_filter(path: Path, reject_ids: dict[str, set[str]]) -> bool:
    split = infer_openimages_split(path)
    if not split:
        return False
    return path.stem in reject_ids.get(split, set())


def copy_background_split(images: list[Path], out_root: Path, split: str, prefix: str) -> int:
    out_images = out_root / "images" / split
    out_labels = out_root / "labels" / split
    ensure_dir(out_images)
    ensure_dir(out_labels)

    copied = 0
    for index, src in enumerate(images, start=1):
        out_name = f"{prefix}_{split}_{index:06d}{src.suffix.lower()}"
        out_image = out_images / out_name
        out_label = out_labels / f"{Path(out_name).stem}.txt"
        shutil.copy2(src, out_image)
        out_label.write_text("")
        copied += 1
    return copied


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Build a YOLO background-only dataset with empty labels."
    )
    parser.add_argument(
        "--src",
        action="append",
        required=True,
        help="Source image file or directory. Repeatable.",
    )
    parser.add_argument("--out", required=True, help="Output YOLO dataset root.")
    parser.add_argument("--seed", type=int, default=42, help="Shuffle seed.")
    parser.add_argument("--train-ratio", type=float, default=0.8, help="Train split ratio.")
    parser.add_argument("--val-ratio", type=float, default=0.1, help="Val split ratio.")
    parser.add_argument("--prefix", default="neg", help="Filename prefix in output dataset.")
    parser.add_argument(
        "--openimages-boxes-root",
        help="Optional Open Images boxes root for excluding images that contain certain classes.",
    )
    parser.add_argument(
        "--openimages-metadata",
        help="Optional Open Images class-descriptions-boxable.csv path.",
    )
    parser.add_argument(
        "--exclude-openimages-class",
        action="append",
        default=[],
        help="Open Images class name to exclude from negatives, e.g. Toilet. Repeatable.",
    )
    args = parser.parse_args()

    if not (0 < args.train_ratio < 1):
        raise SystemExit("--train-ratio must be between 0 and 1")
    if not (0 <= args.val_ratio < 1):
        raise SystemExit("--val-ratio must be between 0 and 1")
    if args.train_ratio + args.val_ratio >= 1:
        raise SystemExit("--train-ratio + --val-ratio must be < 1")

    reject_ids: dict[str, set[str]] = {}
    if args.exclude_openimages_class:
        if not args.openimages_boxes_root or not args.openimages_metadata:
            raise SystemExit(
                "--exclude-openimages-class requires --openimages-boxes-root and --openimages-metadata"
            )
        reject_ids = load_openimages_reject_ids(
            Path(args.openimages_boxes_root),
            Path(args.openimages_metadata),
            args.exclude_openimages_class,
        )

    seen: set[Path] = set()
    candidates: list[Path] = []
    skipped_for_class = 0

    for src in args.src:
        src_path = Path(src)
        if not src_path.exists():
            raise SystemExit(f"Source path does not exist: {src_path}")
        for image_path in iter_input_images(src_path):
            resolved = image_path.resolve()
            if resolved in seen:
                continue
            seen.add(resolved)
            if reject_ids and should_skip_for_openimages_filter(image_path, reject_ids):
                skipped_for_class += 1
                continue
            candidates.append(resolved)

    if not candidates:
        raise SystemExit("No images found for background dataset")

    rnd = random.Random(args.seed)
    rnd.shuffle(candidates)

    total = len(candidates)
    train_count = int(total * args.train_ratio)
    val_count = int(total * args.val_ratio)
    test_count = total - train_count - val_count

    train_images = candidates[:train_count]
    val_images = candidates[train_count : train_count + val_count]
    test_images = candidates[train_count + val_count :]

    out_root = Path(args.out)
    for split in ("train", "val", "test"):
        shutil.rmtree(out_root / "images" / split, ignore_errors=True)
        shutil.rmtree(out_root / "labels" / split, ignore_errors=True)
        ensure_dir(out_root / "images" / split)
        ensure_dir(out_root / "labels" / split)

    copied_train = copy_background_split(train_images, out_root, "train", args.prefix)
    copied_val = copy_background_split(val_images, out_root, "val", args.prefix)
    copied_test = copy_background_split(test_images, out_root, "test", args.prefix)

    print("Background dataset created:")
    print(f"  train: {copied_train}")
    print(f"  val:   {copied_val}")
    print(f"  test:  {copied_test}")
    print(f"  total: {copied_train + copied_val + copied_test}")
    if reject_ids:
        print(f"  skipped_due_to_excluded_openimages_classes: {skipped_for_class}")
        print(
            "  excluded_classes: "
            + ", ".join(sorted({name.strip() for name in args.exclude_openimages_class if name.strip()}))
        )
    print(f"  out:   {out_root}")
    if test_count <= 0:
        print("WARNING: test split is empty. Increase total images or adjust split ratios.")


if __name__ == "__main__":
    main()
