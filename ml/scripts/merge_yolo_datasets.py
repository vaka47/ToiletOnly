import argparse
import shutil
from pathlib import Path


def ensure_dir(path: Path):
    path.mkdir(parents=True, exist_ok=True)


def iter_images(images_dir: Path):
    for p in sorted(images_dir.glob("*")):
        if p.suffix.lower() in (".jpg", ".jpeg", ".png"):
            yield p


def materialize_image(src: Path, dst: Path, image_mode: str):
    if dst.exists() or dst.is_symlink():
        dst.unlink()

    if image_mode == "symlink":
        dst.symlink_to(src.resolve())
    else:
        shutil.copy2(src, dst)


def copy_split(src_root: Path, out_root: Path, split: str, prefix: str, image_mode: str):
    src_images = src_root / "images" / split
    src_labels = src_root / "labels" / split
    if not src_images.exists() or not src_labels.exists():
        return 0

    out_images = out_root / "images" / split
    out_labels = out_root / "labels" / split
    ensure_dir(out_images)
    ensure_dir(out_labels)

    copied = 0
    for img_path in iter_images(src_images):
        lbl_path = src_labels / f"{img_path.stem}.txt"
        if not lbl_path.exists():
            continue

        out_img_name = f"{prefix}_{img_path.name}"
        out_lbl_name = f"{Path(out_img_name).stem}.txt"

        materialize_image(img_path, out_images / out_img_name, image_mode)
        shutil.copy2(lbl_path, out_labels / out_lbl_name)
        copied += 1

    return copied


def parse_source(spec: str):
    if "=" not in spec:
        raise ValueError(f"Invalid --source '{spec}', expected prefix=path")
    prefix, path = spec.split("=", 1)
    prefix = prefix.strip()
    path = path.strip()
    if not prefix or not path:
        raise ValueError(f"Invalid --source '{spec}', expected prefix=path")
    return prefix, Path(path)


def main():
    parser = argparse.ArgumentParser(description="Merge multiple YOLO datasets into one")
    parser.add_argument("--out", required=True, help="Output YOLO dataset root")
    parser.add_argument(
        "--source",
        action="append",
        required=True,
        help="Dataset source in format prefix=/path/to/yolo_root (repeatable)",
    )
    parser.add_argument(
        "--image-mode",
        choices=("copy", "symlink"),
        default="copy",
        help="How to place merged images into the output dataset.",
    )
    args = parser.parse_args()

    out_root = Path(args.out)
    for split in ("train", "val", "test"):
        ensure_dir(out_root / "images" / split)
        ensure_dir(out_root / "labels" / split)

    counts = {}
    for spec in args.source:
        prefix, src_root = parse_source(spec)
        counts[f"{prefix}_train"] = copy_split(src_root, out_root, "train", prefix, args.image_mode)
        counts[f"{prefix}_val"] = copy_split(src_root, out_root, "val", prefix, args.image_mode)
        counts[f"{prefix}_test"] = copy_split(src_root, out_root, "test", prefix, args.image_mode)

    total = sum(counts.values())
    print("Merged dataset created:")
    print(f"  image_mode: {args.image_mode}")
    for key in sorted(counts):
        print(f"  {key}: {counts[key]}")
    print(f"Total copied images: {total}")


if __name__ == "__main__":
    main()
