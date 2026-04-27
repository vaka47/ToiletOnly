#!/usr/bin/env python3
from __future__ import annotations

import argparse
import random
from pathlib import Path


IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".webp", ".bmp"}


def read_lines(path: Path) -> list[str]:
    return [line.strip() for line in path.read_text().splitlines() if line.strip()]


def write_lines(path: Path, lines: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n")


def iter_images(images_dir: Path):
    if not images_dir.exists():
        return
    for path in sorted(images_dir.glob("*")):
        if path.suffix.lower() in IMAGE_EXTENSIONS:
            yield path


def collect_background_lines(dataset_root: Path, split: str) -> list[str]:
    images_dir = dataset_root / "images" / split
    labels_dir = dataset_root / "labels" / split
    lines: list[str] = []
    for image_path in iter_images(images_dir):
        label_path = labels_dir / f"{image_path.stem}.txt"
        if label_path.exists():
            lines.append(str(image_path.resolve()))
    return lines


def dedupe_preserve(lines: list[str]) -> list[str]:
    seen: set[str] = set()
    out: list[str] = []
    for line in lines:
        if line in seen:
            continue
        seen.add(line)
        out.append(line)
    return out


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Append background-only YOLO datasets to an existing list-based dataset."
    )
    parser.add_argument("--base-dir", required=True, help="Directory with base train.txt/val.txt/test.txt files.")
    parser.add_argument(
        "--background-yolo",
        action="append",
        required=True,
        help="Background-only YOLO dataset root. Repeatable.",
    )
    parser.add_argument("--out-dir", required=True, help="Output directory for merged train/val/test lists.")
    parser.add_argument("--yaml-out", help="Optional YAML file to generate for the merged lists.")
    parser.add_argument("--class-name", default="toilet", help="Single class name for YAML output.")
    parser.add_argument("--seed", type=int, default=42, help="Random seed for shuffled output.")
    args = parser.parse_args()

    base_dir = Path(args.base_dir)
    out_dir = Path(args.out_dir)
    rnd = random.Random(args.seed)

    base = {
        split: read_lines(base_dir / f"{split}.txt")
        for split in ("train", "val", "test")
    }
    bg_counts: dict[str, int] = {split: 0 for split in ("train", "val", "test")}
    merged: dict[str, list[str]] = {}

    for split in ("train", "val", "test"):
        combined = list(base[split])
        for dataset in args.background_yolo:
            bg_lines = collect_background_lines(Path(dataset), split)
            bg_counts[split] += len(bg_lines)
            combined.extend(bg_lines)
        combined = dedupe_preserve(combined)
        rnd.shuffle(combined)
        merged[split] = combined
        write_lines(out_dir / f"{split}.txt", combined)

    if args.yaml_out:
        yaml_path = Path(args.yaml_out)
        yaml_path.parent.mkdir(parents=True, exist_ok=True)
        yaml_path.write_text(
            "\n".join(
                [
                    f"train: {(out_dir / 'train.txt').resolve()}",
                    f"val: {(out_dir / 'val.txt').resolve()}",
                    f"test: {(out_dir / 'test.txt').resolve()}",
                    "",
                    "names:",
                    f"  0: {args.class_name}",
                    "",
                ]
            )
        )

    print("Merged list dataset created:")
    for split in ("train", "val", "test"):
        print(
            f"  {split}: base={len(base[split])}, backgrounds={bg_counts[split]}, total={len(merged[split])}"
        )
    print(f"  out_dir: {out_dir.resolve()}")
    if args.yaml_out:
        print(f"  yaml:    {Path(args.yaml_out).resolve()}")


if __name__ == "__main__":
    main()
