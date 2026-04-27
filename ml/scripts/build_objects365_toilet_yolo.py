import argparse
import json
import shutil
from collections import defaultdict
from pathlib import Path


def ensure_dir(path: Path):
    path.mkdir(parents=True, exist_ok=True)


def find_toilet_category_ids(categories):
    toilet_ids = set()
    for c in categories:
        name = str(c.get("name", "")).strip().lower()
        if name == "toilet":
            toilet_ids.add(int(c["id"]))
    return toilet_ids


def index_images(root: Path):
    index = {}
    for ext in ("*.jpg", "*.jpeg", "*.png"):
        for p in root.rglob(ext):
            index[p.name] = p
    return index


def yolo_line_from_bbox(bbox, width: float, height: float):
    x, y, w, h = bbox
    if w <= 1 or h <= 1:
        return None
    xc = (x + w / 2.0) / width
    yc = (y + h / 2.0) / height
    wn = w / width
    hn = h / height
    return f"0 {xc:.6f} {yc:.6f} {wn:.6f} {hn:.6f}"


def convert(annotations_json: Path, images_root: Path, out_root: Path, split: str):
    data = json.loads(annotations_json.read_text())
    toilet_ids = find_toilet_category_ids(data.get("categories", []))
    if not toilet_ids:
        raise RuntimeError("Category 'toilet' not found in Objects365 annotations")

    anns_by_image = defaultdict(list)
    for ann in data.get("annotations", []):
        if int(ann.get("category_id", -1)) in toilet_ids:
            anns_by_image[int(ann["image_id"])].append(ann)

    images = data.get("images", [])
    images_by_id = {int(im["id"]): im for im in images}

    img_index = index_images(images_root)
    out_images = out_root / "images" / split
    out_labels = out_root / "labels" / split
    ensure_dir(out_images)
    ensure_dir(out_labels)

    copied = 0
    for image_id, anns in anns_by_image.items():
        im = images_by_id.get(image_id)
        if not im:
            continue

        file_name = Path(str(im.get("file_name", ""))).name
        width = float(im.get("width", 0))
        height = float(im.get("height", 0))
        if not file_name or width <= 0 or height <= 0:
            continue

        src = images_root / file_name
        if not src.exists():
            src = img_index.get(file_name)
            if src is None:
                continue

        yolo_lines = []
        for ann in anns:
            line = yolo_line_from_bbox(ann.get("bbox", [0, 0, 0, 0]), width, height)
            if line:
                yolo_lines.append(line)
        if not yolo_lines:
            continue

        out_img_name = f"o365_{file_name}"
        out_lbl_name = f"{Path(out_img_name).stem}.txt"
        shutil.copy2(src, out_images / out_img_name)
        (out_labels / out_lbl_name).write_text("\n".join(yolo_lines) + "\n")
        copied += 1

    return copied


def parse_args():
    parser = argparse.ArgumentParser(description="Build YOLO toilet subset from Objects365")
    parser.add_argument("--annotations", required=True, help="Path to Objects365 JSON annotation file")
    parser.add_argument("--images-root", required=True, help="Root dir with extracted Objects365 images")
    parser.add_argument("--out", default="/Users/vaka47/Dev/Приложение в туалете/ml/data/objects365_toilet", help="Output YOLO dataset root")
    parser.add_argument("--split", default="train", choices=["train", "val", "test"], help="Destination split")
    return parser.parse_args()


def main():
    args = parse_args()
    copied = convert(
        annotations_json=Path(args.annotations),
        images_root=Path(args.images_root),
        out_root=Path(args.out),
        split=args.split,
    )
    print(f"Objects365 conversion complete: {copied} images in split '{args.split}'")


if __name__ == "__main__":
    main()
