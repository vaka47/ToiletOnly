import argparse
import concurrent.futures
import json
import random
import shutil
import urllib.request
import zipfile
from collections import defaultdict
from pathlib import Path


ANNOTATIONS_URL = "http://images.cocodataset.org/annotations/annotations_trainval2017.zip"


def ensure_dir(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True)


def download_file(url: str, out_path: Path) -> None:
    if out_path.exists():
        return
    ensure_dir(out_path.parent)
    urllib.request.urlretrieve(url, out_path)


def load_annotations(zip_path: Path, member: str):
    with zipfile.ZipFile(zip_path, "r") as zf:
        with zf.open(member) as fh:
            return json.load(fh)


def convert_split(
    ann: dict,
    split_name: str,
    out_root: Path,
    limit: int,
    seed: int,
    workers: int,
):
    categories = ann.get("categories", [])
    toilet_ids = {c["id"] for c in categories if c.get("name") == "toilet"}
    if not toilet_ids:
        raise RuntimeError("Could not find category 'toilet' in COCO annotations")

    annotations_by_image = defaultdict(list)
    for a in ann.get("annotations", []):
        if a.get("category_id") in toilet_ids and a.get("iscrowd", 0) == 0:
            annotations_by_image[a["image_id"]].append(a)

    images = [img for img in ann.get("images", []) if img["id"] in annotations_by_image]
    if limit > 0 and len(images) > limit:
        rng = random.Random(seed)
        rng.shuffle(images)
        images = images[:limit]

    out_images = out_root / "images" / split_name
    out_labels = out_root / "labels" / split_name
    ensure_dir(out_images)
    ensure_dir(out_labels)

    tasks = []
    for img in images:
        width = float(img["width"])
        height = float(img["height"])
        anns = annotations_by_image.get(img["id"], [])
        if not anns:
            continue

        yolo_lines = []
        for a in anns:
            x, y, w, h = a["bbox"]
            if w <= 1 or h <= 1:
                continue
            xc = (x + w / 2.0) / width
            yc = (y + h / 2.0) / height
            wn = w / width
            hn = h / height
            yolo_lines.append(f"0 {xc:.6f} {yc:.6f} {wn:.6f} {hn:.6f}")

        if not yolo_lines:
            continue

        file_name = img["file_name"]
        img_url = img.get("coco_url")
        if not img_url:
            # Fallback to the canonical path.
            folder = "train2017" if split_name == "train" else "val2017"
            img_url = f"http://images.cocodataset.org/{folder}/{file_name}"

        out_img = out_images / file_name
        out_lbl = out_labels / f"{Path(file_name).stem}.txt"

        tasks.append((img_url, out_img, out_lbl, yolo_lines))

    def worker(task):
        img_url, out_img, out_lbl, yolo_lines = task
        try:
            download_file(img_url, out_img)
        except Exception:
            return 0
        out_lbl.write_text("\n".join(yolo_lines) + "\n")
        return 1

    kept = 0
    with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as pool:
        for ok in pool.map(worker, tasks):
            kept += ok
    return kept


def create_test_from_val(out_root: Path, test_ratio: float, seed: int):
    val_images = sorted((out_root / "images" / "val").glob("*.jpg"))
    val_images += sorted((out_root / "images" / "val").glob("*.png"))
    if not val_images:
        return 0

    rng = random.Random(seed)
    rng.shuffle(val_images)
    test_count = max(1, int(len(val_images) * test_ratio))
    test_images = val_images[:test_count]

    test_img_dir = out_root / "images" / "test"
    test_lbl_dir = out_root / "labels" / "test"
    ensure_dir(test_img_dir)
    ensure_dir(test_lbl_dir)

    moved = 0
    for img_path in test_images:
        lbl_path = out_root / "labels" / "val" / f"{img_path.stem}.txt"
        if not lbl_path.exists():
            continue
        shutil.move(str(img_path), str(test_img_dir / img_path.name))
        shutil.move(str(lbl_path), str(test_lbl_dir / lbl_path.name))
        moved += 1
    return moved


def parse_args():
    parser = argparse.ArgumentParser(description="Download COCO toilet subset and convert to YOLO")
    parser.add_argument(
        "--out",
        default="/Users/vaka47/Dev/Приложение в туалете/ml/data/coco_toilet",
        help="Output YOLO dataset root",
    )
    parser.add_argument(
        "--cache",
        default="/Users/vaka47/Dev/Приложение в туалете/ml/data/coco_cache",
        help="Cache directory for COCO annotation zip",
    )
    parser.add_argument("--train-limit", type=int, default=2500, help="Max train images (0=no limit)")
    parser.add_argument("--val-limit", type=int, default=800, help="Max val images before val/test split (0=no limit)")
    parser.add_argument("--test-ratio-from-val", type=float, default=0.3, help="Fraction of val moved to test")
    parser.add_argument("--seed", type=int, default=47, help="Random seed")
    parser.add_argument("--workers", type=int, default=16, help="Parallel download workers")
    return parser.parse_args()


def main():
    args = parse_args()
    out_root = Path(args.out)
    cache_root = Path(args.cache)
    ensure_dir(cache_root)

    ann_zip = cache_root / "annotations_trainval2017.zip"
    download_file(ANNOTATIONS_URL, ann_zip)

    train_ann = load_annotations(ann_zip, "annotations/instances_train2017.json")
    val_ann = load_annotations(ann_zip, "annotations/instances_val2017.json")

    train_kept = convert_split(
        train_ann,
        split_name="train",
        out_root=out_root,
        limit=args.train_limit,
        seed=args.seed,
        workers=args.workers,
    )
    val_kept = convert_split(
        val_ann,
        split_name="val",
        out_root=out_root,
        limit=args.val_limit,
        seed=args.seed + 1,
        workers=args.workers,
    )
    moved_to_test = create_test_from_val(
        out_root=out_root,
        test_ratio=args.test_ratio_from_val,
        seed=args.seed + 2,
    )

    print("COCO toilet subset prepared:")
    print(f"  train images: {train_kept}")
    print(f"  val images before test split: {val_kept}")
    print(f"  moved from val to test: {moved_to_test}")
    print(f"  final val images: {val_kept - moved_to_test}")
    print(f"  final test images: {moved_to_test}")


if __name__ == "__main__":
    main()
