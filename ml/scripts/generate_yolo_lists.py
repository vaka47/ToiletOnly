#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path


IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".webp", ".bmp"}


def iter_images(images_dir: Path):
    if not images_dir.exists():
        return
    for path in sorted(images_dir.glob("*")):
        if path.suffix.lower() in IMAGE_EXTENSIONS:
            yield path


def write_lines(path: Path, lines: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n")


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate train/val/test image list files from a YOLO dataset.")
    parser.add_argument("--dataset", required=True, help="YOLO dataset root.")
    parser.add_argument("--out-dir", required=True, help="Directory where train.txt/val.txt/test.txt will be written.")
    parser.add_argument("--yaml-out", help="Optional dataset YAML path to write.")
    parser.add_argument("--class-name", default="toilet", help="Single class name for YAML output.")
    args = parser.parse_args()

    dataset_root = Path(args.dataset)
    out_dir = Path(args.out_dir)

    counts: dict[str, int] = {}
    generated_paths: dict[str, Path] = {}

    for split in ("train", "val", "test"):
        images_dir = dataset_root / "images" / split
        labels_dir = dataset_root / "labels" / split
        lines: list[str] = []
        for image_path in iter_images(images_dir):
            label_path = labels_dir / f"{image_path.stem}.txt"
            if label_path.exists():
                lines.append(str(image_path.resolve()))
        write_lines(out_dir / f"{split}.txt", lines)
        counts[split] = len(lines)
        generated_paths[split] = (out_dir / f"{split}.txt").resolve()

    if args.yaml_out:
        yaml_path = Path(args.yaml_out)
        yaml_path.parent.mkdir(parents=True, exist_ok=True)
        yaml_path.write_text(
            "\n".join(
                [
                    f"train: {generated_paths['train']}",
                    f"val: {generated_paths['val']}",
                    f"test: {generated_paths['test']}",
                    "",
                    "names:",
                    f"  0: {args.class_name}",
                    "",
                ]
            )
        )

    print("Generated YOLO list files:")
    for split in ("train", "val", "test"):
        print(f"  {split}: {counts[split]} -> {generated_paths[split]}")
    if args.yaml_out:
        print(f"  yaml: {Path(args.yaml_out).resolve()}")


if __name__ == "__main__":
    main()
