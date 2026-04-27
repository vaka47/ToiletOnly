import argparse
import random
import shutil
from pathlib import Path

from PIL import Image, ImageEnhance, ImageFilter


def ensure_dir(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True)


def parse_labels(label_path: Path):
    labels = []
    if not label_path.exists():
        return labels

    for line in label_path.read_text().splitlines():
        parts = line.strip().split()
        if len(parts) != 5:
            continue
        cls, x, y, w, h = parts
        try:
            labels.append((int(cls), float(x), float(y), float(w), float(h)))
        except ValueError:
            continue
    return labels


def format_labels(labels) -> str:
    return "\n".join(
        f"{cls} {x:.6f} {y:.6f} {w:.6f} {h:.6f}" for cls, x, y, w, h in labels
    ) + "\n"


def apply_augmentations(image: Image.Image, labels, rng: random.Random):
    out = image.copy()
    out_labels = labels

    # Horizontal flip is the only geometric transform here; update x-center.
    if rng.random() < 0.5:
        out = out.transpose(Image.FLIP_LEFT_RIGHT)
        out_labels = [(cls, 1.0 - x, y, w, h) for cls, x, y, w, h in out_labels]

    out = ImageEnhance.Brightness(out).enhance(rng.uniform(0.75, 1.25))
    out = ImageEnhance.Contrast(out).enhance(rng.uniform(0.75, 1.25))
    out = ImageEnhance.Color(out).enhance(rng.uniform(0.8, 1.2))

    if rng.random() < 0.3:
        out = out.filter(ImageFilter.GaussianBlur(radius=rng.uniform(0.2, 1.0)))

    return out, out_labels


def copy_split(src_root: Path, out_root: Path, split: str):
    src_images = src_root / "images" / split
    src_labels = src_root / "labels" / split
    out_images = out_root / "images" / split
    out_labels = out_root / "labels" / split

    ensure_dir(out_images)
    ensure_dir(out_labels)

    copied = 0
    for img_path in sorted(src_images.glob("*")):
        if img_path.suffix.lower() not in (".jpg", ".jpeg", ".png"):
            continue
        lbl_path = src_labels / f"{img_path.stem}.txt"
        if not lbl_path.exists():
            continue
        shutil.copy2(img_path, out_images / img_path.name)
        shutil.copy2(lbl_path, out_labels / lbl_path.name)
        copied += 1
    return copied


def augment_train_split(src_root: Path, out_root: Path, copies_per_image: int, seed: int):
    rng = random.Random(seed)
    src_images = src_root / "images" / "train"
    src_labels = src_root / "labels" / "train"
    out_images = out_root / "images" / "train"
    out_labels = out_root / "labels" / "train"

    ensure_dir(out_images)
    ensure_dir(out_labels)

    augmented = 0
    for img_path in sorted(src_images.glob("*")):
        if img_path.suffix.lower() not in (".jpg", ".jpeg", ".png"):
            continue
        lbl_path = src_labels / f"{img_path.stem}.txt"
        labels = parse_labels(lbl_path)
        if not labels:
            continue

        try:
            image = Image.open(img_path).convert("RGB")
        except Exception:
            continue

        for i in range(copies_per_image):
            aug_img, aug_labels = apply_augmentations(image, labels, rng)
            out_name = f"{img_path.stem}__aug{i + 1:02d}.jpg"
            aug_img.save(out_images / out_name, quality=95)
            (out_labels / f"{Path(out_name).stem}.txt").write_text(format_labels(aug_labels))
            augmented += 1

    return augmented


def main():
    parser = argparse.ArgumentParser(description="Create augmented YOLO dataset copy")
    parser.add_argument("--src", required=True, help="Source YOLO dataset root")
    parser.add_argument("--out", required=True, help="Output YOLO dataset root")
    parser.add_argument(
        "--train-copies",
        type=int,
        default=1,
        help="How many augmented copies to create per train image",
    )
    parser.add_argument("--seed", type=int, default=42, help="Random seed")
    args = parser.parse_args()

    if args.train_copies < 1:
        raise ValueError("--train-copies must be >= 1")

    src_root = Path(args.src)
    out_root = Path(args.out)

    copied_train = copy_split(src_root, out_root, "train")
    copied_val = copy_split(src_root, out_root, "val")
    copied_test = copy_split(src_root, out_root, "test")
    augmented_train = augment_train_split(src_root, out_root, args.train_copies, args.seed)

    print("Augmented dataset created:")
    print(f"  train originals: {copied_train}")
    print(f"  val originals: {copied_val}")
    print(f"  test originals: {copied_test}")
    print(f"  train augmentations added: {augmented_train}")
    print(f"  total train images: {copied_train + augmented_train}")


if __name__ == "__main__":
    main()
