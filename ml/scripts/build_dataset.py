import argparse
import shutil
from pathlib import Path

from PIL import Image


def ensure_dir(path: Path):
    path.mkdir(parents=True, exist_ok=True)


def clamp(v, lo, hi):
    return max(lo, min(hi, v))


def convert_openimages_split(split_dir: Path, out_images: Path, out_labels: Path, prefix: str):
    image_dir = split_dir / "toilet"
    label_dir = image_dir / "labels"
    if not image_dir.exists():
        return 0

    count = 0
    for img_path in image_dir.glob("*.jpg"):
        label_path = label_dir / f"{img_path.stem}.txt"
        if not label_path.exists():
            continue

        try:
            with Image.open(img_path) as im:
                w, h = im.size
        except Exception:
            continue

        yolo_lines = []
        for line in label_path.read_text().strip().splitlines():
            parts = line.split()
            if len(parts) != 5:
                continue
            _, x_min, y_min, x_max, y_max = parts
            try:
                x_min = float(x_min)
                y_min = float(y_min)
                x_max = float(x_max)
                y_max = float(y_max)
            except ValueError:
                continue

            x_min = clamp(x_min, 0.0, float(w))
            y_min = clamp(y_min, 0.0, float(h))
            x_max = clamp(x_max, 0.0, float(w))
            y_max = clamp(y_max, 0.0, float(h))

            bw = x_max - x_min
            bh = y_max - y_min
            if bw <= 1 or bh <= 1:
                continue

            x_center = (x_min + x_max) / 2.0 / w
            y_center = (y_min + y_max) / 2.0 / h
            bw_norm = bw / w
            bh_norm = bh / h

            yolo_lines.append(f"0 {x_center:.6f} {y_center:.6f} {bw_norm:.6f} {bh_norm:.6f}")

        if not yolo_lines:
            continue

        out_name = f"{prefix}_{img_path.name}"
        out_img = out_images / out_name
        out_lbl = out_labels / f"{Path(out_name).stem}.txt"

        shutil.copy2(img_path, out_img)
        out_lbl.write_text("\n".join(yolo_lines) + "\n")
        count += 1

    return count


def convert_roboflow_split(split_dir: Path, out_images: Path, out_labels: Path, prefix: str):
    image_dir = split_dir / "images"
    label_dir = split_dir / "labels"
    if not image_dir.exists():
        return 0

    count = 0
    for lbl_path in label_dir.glob("*.txt"):
        img_path = image_dir / f"{lbl_path.stem}.jpg"
        if not img_path.exists():
            img_path = image_dir / f"{lbl_path.stem}.png"
        if not img_path.exists():
            continue

        yolo_lines = []
        for line in lbl_path.read_text().strip().splitlines():
            parts = line.split()
            if len(parts) != 5:
                continue
            cls, x, y, w, h = parts
            try:
                cls = int(cls)
            except ValueError:
                continue

            if cls not in (6, 9):
                continue

            try:
                x = float(x)
                y = float(y)
                w = float(w)
                h = float(h)
            except ValueError:
                continue

            yolo_lines.append(f"0 {x:.6f} {y:.6f} {w:.6f} {h:.6f}")

        if not yolo_lines:
            continue

        out_name = f"{prefix}_{img_path.name}"
        out_img = out_images / out_name
        out_lbl = out_labels / f"{Path(out_name).stem}.txt"

        shutil.copy2(img_path, out_img)
        out_lbl.write_text("\n".join(yolo_lines) + "\n")
        count += 1

    return count


def main():
    parser = argparse.ArgumentParser(description="Build merged YOLO dataset from Open Images + Roboflow")
    parser.add_argument("--openimages", required=True, help="Open Images root directory")
    parser.add_argument("--roboflow", required=True, help="Roboflow dataset root directory")
    parser.add_argument("--out", required=True, help="Output dataset root")
    args = parser.parse_args()

    out_root = Path(args.out)
    for split in ("train", "val", "test"):
        ensure_dir(out_root / "images" / split)
        ensure_dir(out_root / "labels" / split)

    oi_root = Path(args.openimages)
    rf_root = Path(args.roboflow)

    counts = {}

    counts["oi_train"] = convert_openimages_split(
        oi_root / "train",
        out_root / "images" / "train",
        out_root / "labels" / "train",
        "oi_train",
    )
    counts["oi_val"] = convert_openimages_split(
        oi_root / "validation",
        out_root / "images" / "val",
        out_root / "labels" / "val",
        "oi_val",
    )
    counts["oi_test"] = convert_openimages_split(
        oi_root / "test",
        out_root / "images" / "test",
        out_root / "labels" / "test",
        "oi_test",
    )

    counts["rf_train"] = convert_roboflow_split(
        rf_root / "train",
        out_root / "images" / "train",
        out_root / "labels" / "train",
        "rf_train",
    )
    counts["rf_val"] = convert_roboflow_split(
        rf_root / "valid",
        out_root / "images" / "val",
        out_root / "labels" / "val",
        "rf_val",
    )
    counts["rf_test"] = convert_roboflow_split(
        rf_root / "test",
        out_root / "images" / "test",
        out_root / "labels" / "test",
        "rf_test",
    )

    total = sum(counts.values())
    print("Dataset build complete:")
    for k, v in counts.items():
        print(f"  {k}: {v}")
    print(f"Total labeled images: {total}")


if __name__ == "__main__":
    main()
