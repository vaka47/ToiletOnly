#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import shutil
from collections import Counter, defaultdict
from pathlib import Path


IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png"}


def ensure_dir(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True)


def load_class_file(path: Path) -> list[str]:
    classes: list[str] = []
    for raw_line in path.read_text().splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        classes.append(line)
    return classes


def index_images(root: Path) -> dict[str, Path]:
    index: dict[str, Path] = {}
    for ext in IMAGE_EXTENSIONS:
        for path in root.rglob(f"*{ext}"):
            index[path.name] = path
    return index


def resolve_category_ids(categories: list[dict], class_names: list[str]) -> tuple[set[int], dict[int, str]]:
    wanted = {name.strip().lower() for name in class_names if name.strip()}
    ids: set[int] = set()
    names_by_id: dict[int, str] = {}

    for category in categories:
        name = str(category.get("name", "")).strip()
        lowered = name.lower()
        if lowered in wanted:
            category_id = int(category["id"])
            ids.add(category_id)
            names_by_id[category_id] = name

    missing = sorted(wanted - {name.lower() for name in names_by_id.values()})
    if missing:
        raise RuntimeError(
            "Objects365 categories not found: " + ", ".join(missing)
        )

    return ids, names_by_id


def convert(
    annotations_json: Path,
    images_root: Path,
    out_root: Path,
    split: str,
    class_names: list[str],
    exclude_class_names: list[str],
    prefix: str,
    limit: int,
) -> tuple[int, int, Counter[str]]:
    with annotations_json.open("r") as fh:
        data = json.load(fh)

    categories = data.get("categories", [])
    wanted_ids, wanted_names_by_id = resolve_category_ids(categories, class_names)
    exclude_ids, _ = resolve_category_ids(categories, exclude_class_names)

    target_classes_by_image: dict[int, set[int]] = defaultdict(set)
    excluded_images: set[int] = set()

    for ann in data.get("annotations", []):
        image_id = int(ann.get("image_id", -1))
        category_id = int(ann.get("category_id", -1))
        if category_id in wanted_ids:
            target_classes_by_image[image_id].add(category_id)
        if category_id in exclude_ids:
            excluded_images.add(image_id)

    images_by_id = {int(im["id"]): im for im in data.get("images", [])}
    image_index = index_images(images_root)

    out_images = out_root / "images" / split
    out_labels = out_root / "labels" / split
    shutil.rmtree(out_images, ignore_errors=True)
    shutil.rmtree(out_labels, ignore_errors=True)
    ensure_dir(out_images)
    ensure_dir(out_labels)

    copied = 0
    skipped_with_excluded_class = 0
    per_class_counts: Counter[str] = Counter()

    for image_id in sorted(target_classes_by_image):
        if image_id in excluded_images:
            skipped_with_excluded_class += 1
            continue

        image_info = images_by_id.get(image_id)
        if not image_info:
            continue

        file_name = Path(str(image_info.get("file_name", ""))).name
        if not file_name:
            continue

        src = images_root / file_name
        if not src.exists():
            src = image_index.get(file_name)
            if src is None:
                continue

        out_name = f"{prefix}_{file_name}"
        shutil.copy2(src, out_images / out_name)
        (out_labels / f"{Path(out_name).stem}.txt").write_text("")
        copied += 1

        for category_id in target_classes_by_image[image_id]:
            per_class_counts[wanted_names_by_id[category_id]] += 1

        if limit > 0 and copied >= limit:
            break

    return copied, skipped_with_excluded_class, per_class_counts


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Build a YOLO background-only dataset from Objects365 classes."
    )
    parser.add_argument("--annotations", required=True, help="Path to Objects365 JSON annotation file.")
    parser.add_argument("--images-root", required=True, help="Root dir with extracted Objects365 images.")
    parser.add_argument("--out", required=True, help="Output YOLO dataset root.")
    parser.add_argument("--split", default="train", choices=["train", "val", "test"], help="Destination split.")
    parser.add_argument(
        "--class",
        dest="classes",
        action="append",
        help="Objects365 class to include as negative/background. Repeatable.",
    )
    parser.add_argument(
        "--class-file",
        help="Optional text file with Objects365 classes to include, one per line.",
    )
    parser.add_argument(
        "--exclude-class",
        dest="exclude_classes",
        action="append",
        default=["Toilet"],
        help="Objects365 class that must exclude an image from negatives. Repeatable.",
    )
    parser.add_argument("--prefix", default="o365neg", help="Output filename prefix.")
    parser.add_argument("--limit", type=int, default=0, help="Optional max number of copied images. 0 means no limit.")
    args = parser.parse_args()

    classes = list(args.classes or [])
    if args.class_file:
        classes.extend(load_class_file(Path(args.class_file)))

    if not classes:
        parser.error("at least one --class or --class-file is required")

    args.classes = classes
    return args


def main() -> None:
    args = parse_args()
    copied, skipped, per_class_counts = convert(
        annotations_json=Path(args.annotations),
        images_root=Path(args.images_root),
        out_root=Path(args.out),
        split=args.split,
        class_names=args.classes,
        exclude_class_names=args.exclude_classes,
        prefix=args.prefix,
        limit=args.limit,
    )

    print("Objects365 background conversion complete:")
    print(f"  split: {args.split}")
    print(f"  copied: {copied}")
    print(f"  skipped_due_to_excluded_class: {skipped}")
    print(f"  out: {Path(args.out).resolve()}")
    print("  classes:")
    for name, count in sorted(per_class_counts.items()):
        print(f"    {name}: {count}")


if __name__ == "__main__":
    main()
