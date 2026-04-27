# ToiletDetector ML pipeline

Goal: train an on-device Core ML object detector that recognizes a toilet and unlocks the app.

## Recommended approach
1) Bootstrap with public data + your own photos for your real bathrooms.
2) Fine-tune on your own images to reduce false positives.
3) Export to Core ML and embed in the app as `ToiletDetector.mlmodel`.

## Data collection
You need 1–3k labeled images to start. Mix:
- Your own photos (different toilets, angles, lighting, devices).
- Public datasets for toilets (helps coverage, then fine-tune with your own).
- Hard negatives: images and video frames that must not unlock the app.

Capture guidelines:
- Include different angles, distances, partial occlusions (lid closed, seat up/down).
- Include negatives: sinks, showers, bathtubs, garbage bins.
- Add many hard negatives with white furniture and bathroom/kitchen surfaces: chair, stool, refrigerator, cabinetry, towels, bedsheets, countertops, washing machine, dishwasher, doors.
- Avoid people in the frame for privacy.

## Licensing (important)
- Open Images: annotations are CC BY, but image licenses vary per image. You must comply with each image's license.
- Objects365: non-commercial license (do not use in commercial apps).
- Roboflow Universe: licensing depends on the dataset; check the dataset page.

## Automated downloads
Scripts live in `ml/scripts`:
- `download_openimages.sh` uses oidv6 to fetch class `Toilet`.
- `download_openimages_hard_negatives.sh` fetches class-specific negative packs from Open Images.
- `download_roboflow.py` downloads a Roboflow dataset (YOLOv8 format).
- `download_objects365.sh` downloads Objects365 from URLs you provide (not for commercial use).
- `download_coco_toilet.py` downloads and converts a COCO toilet subset to YOLO format.
- `merge_yolo_datasets.py` merges multiple YOLO datasets into one.
- `build_background_yolo_dataset.py` converts arbitrary negative images into a YOLO dataset with empty labels.
- `build_objects365_background_yolo.py` converts selected Objects365 classes into a YOLO background dataset with empty labels.
- `extract_video_frames.py` extracts video frames for hard negatives.
- `generate_yolo_lists.py` writes `train.txt`/`val.txt`/`test.txt` from a YOLO dataset.
- `prepare_hard_negative_dataset.sh` builds and merges a background dataset, then emits ready list files and YAML.
- `bootstrap_hard_negative_dataset.sh` downloads Open Images negatives, optionally extracts your video frames, optionally converts Objects365 negatives, then builds a merged YOLO dataset.
- `download_all.sh` runs Open Images + Roboflow only (commercial-safe).

### Open Images
By default, the download script limits each split to keep the dataset small:
- train: 2000
- validation: 400
- test: 400

Override limits via env vars if needed: `LIMIT_TRAIN`, `LIMIT_VAL`, `LIMIT_TEST`.

```
/Users/vaka47/Dev/Приложение в туалете/ml/scripts/download_openimages.sh \
  /Users/vaka47/Dev/Приложение в туалете/ml/data/openimages
```

### Open Images hard negatives
Default classes live in:
`/Users/vaka47/Dev/Приложение в туалете/ml/data/openimages_hard_negative_classes.txt`

Default limits per class are conservative to fit a small external drive:
- train: 60
- validation: 15
- test: 15

Override if needed with:
`LIMIT_TRAIN_PER_CLASS`, `LIMIT_VAL_PER_CLASS`, `LIMIT_TEST_PER_CLASS`

Download ready-made packs for classes like `Chair`, `Refrigerator`, `Towel`, `Bed`, `Cabinetry`, `Washing machine`:
```
/Users/vaka47/Dev/Приложение в туалете/ml/scripts/download_openimages_hard_negatives.sh \
  /Users/vaka47/Dev/Приложение в туалете/ml/data/openimages_hard_negatives \
  /Users/vaka47/Dev/Приложение в туалете/ml/data/openimages_hard_negative_classes.txt
```

Official source references for ready-made negative packs:
`/Users/vaka47/Dev/Приложение в туалете/ml/data/negative_pack_sources.md`

### Objects365 hard negatives (non-commercial only)
Default classes live in:
`/Users/vaka47/Dev/Приложение в туалете/ml/data/objects365_hard_negative_classes.txt`

After downloading/extracting Objects365 images, build a background-only dataset:
```
python3 /Users/vaka47/Dev/Приложение в туалете/ml/scripts/build_objects365_background_yolo.py \
  --annotations /Users/vaka47/Dev/Приложение в туалете/ml/data/objects365/zhiyuan_objv2_val.json \
  --images-root /Volumes/Untitled/ToiletML/data/objects365_val \
  --out /Volumes/Untitled/ToiletML/data/objects365_hard_negatives_yolo \
  --split train \
  --class Chair \
  --class Refrigerator \
  --class Bed \
  --class Sink \
  --class Bathtub \
  --class Towel \
  --class Mirror \
  --class "Washing Machine/Drying Machine" \
  --class "Cabinet/shelf" \
  --class "Toilet Paper" \
  --class Urinal
```

### Extract hard-negative frames from your videos
This requires `ffmpeg`.
```
python3 /Users/vaka47/Dev/Приложение в туалете/ml/scripts/extract_video_frames.py \
  --src /path/to/negative_videos \
  --out /Volumes/Untitled/ToiletML/data/negatives_from_video \
  --every-seconds 2
```

### Build a background-only YOLO dataset from negative images
This creates empty `.txt` labels and can exclude any Open Images images that also contain a `Toilet`.
```
python3 /Users/vaka47/Dev/Приложение в туалете/ml/scripts/build_background_yolo_dataset.py \
  --src /Users/vaka47/Dev/Приложение в туалете/ml/data/openimages_hard_negatives \
  --src /Volumes/Untitled/ToiletML/data/negatives_from_video \
  --out /Volumes/Untitled/ToiletML/data/background_negatives_yolo \
  --openimages-boxes-root /Users/vaka47/Dev/Приложение в туалете/ml/data/openimages/boxes \
  --openimages-metadata /Users/vaka47/Dev/Приложение в туалете/ml/data/openimages/metadata/class-descriptions-boxable.csv \
  --exclude-openimages-class Toilet
```

### Merge positives + hard negatives and generate list-based YAML
By default, `prepare_hard_negative_dataset.sh` merges images as symlinks to save disk space.

```
/Users/vaka47/Dev/Приложение в туалете/ml/scripts/prepare_hard_negative_dataset.sh \
  --base-yolo /Users/vaka47/Dev/Приложение в туалете/ml/data/dataset_aug \
  --negative-src /Users/vaka47/Dev/Приложение в туалете/ml/data/openimages_hard_negatives \
  --negative-src /Volumes/Untitled/ToiletML/data/negatives_from_video \
  --out-dataset /Volumes/Untitled/ToiletML/data/dataset_noncommercial_v6 \
  --lists-out /Volumes/Untitled/ToiletML/data/lists_v6 \
  --yaml-out /Users/vaka47/Dev/Приложение в туалете/ml/data/toilet_noncommercial_v6_lists.yaml \
  --work-dir /Volumes/Untitled/ToiletML/data/work_v6
```

### Fastest path for your current `v5` list-based dataset
Your latest real training run used:
`/Volumes/Untitled/ToiletML/data/lists_v5`

For the next retrain, keep that base and append hard negatives to the lists:

```
/Users/vaka47/Dev/Приложение в туалете/ml/scripts/prepare_hard_negative_lists_from_v5.sh \
  --base-lists /Volumes/Untitled/ToiletML/data/lists_v5 \
  --video-src /Volumes/Untitled/ToiletML/data/negative_videos \
  --objects365-images-root /Volumes/Untitled/ToiletML/data/objects365_val \
  --lists-out /Users/vaka47/Dev/Приложение в туалете/ml/data/lists_v6_from_v5 \
  --yaml-out /Users/vaka47/Dev/Приложение в туалете/ml/data/toilet_noncommercial_v6_from_v5_lists.yaml \
  --work-dir /Volumes/Untitled/ToiletML/data/work_v6_from_v5
```

If Open Images hard-negative packs are already downloaded, add:
```
  --skip-openimages-download
```

Then train:
```
yolo detect train \
  model="/Users/vaka47/Dev/Приложение в туалете/yolov8n.pt" \
  data="/Users/vaka47/Dev/Приложение в туалете/ml/data/toilet_noncommercial_v6_from_v5_lists.yaml" \
  epochs=40 imgsz=448 batch=8 device=cpu workers=0 \
  project="/Volumes/Untitled/ToiletML/runs" name=toilet_v6_from_v5_hardneg
```

### One-shot hard-negative bootstrap
This is the quickest path for your current problem: ready-made Open Images packs + your own negative videos + optional Objects365 indoor negatives.
```
/Users/vaka47/Dev/Приложение в туалете/ml/scripts/bootstrap_hard_negative_dataset.sh \
  --base-yolo /Users/vaka47/Dev/Приложение в туалете/ml/data/dataset_aug \
  --video-src /Volumes/Untitled/ToiletML/data/negative_videos \
  --objects365-images-root /Volumes/Untitled/ToiletML/data/objects365_val \
  --out-dataset /Volumes/Untitled/ToiletML/data/dataset_noncommercial_v6 \
  --lists-out /Volumes/Untitled/ToiletML/data/lists_v6 \
  --yaml-out /Users/vaka47/Dev/Приложение в туалете/ml/data/toilet_noncommercial_v6_lists.yaml \
  --work-dir /Volumes/Untitled/ToiletML/data/work_v6
```

If Open Images packs are already downloaded, add:
```
  --skip-openimages-download
```

### Roboflow (YOLOv8 format)
```
export ROBOFLOW_API_KEY="YOUR_KEY"
python3 /Users/vaka47/Dev/Приложение в туалете/ml/scripts/download_roboflow.py \
  --workspace "YOUR_WORKSPACE" \
  --project "YOUR_PROJECT" \
  --version 1 \
  --out "/Users/vaka47/Dev/Приложение в туалете/ml/data/roboflow"
```

### Objects365 (non-commercial only)
1) Put official download URLs into:
```
/Users/vaka47/Dev/Приложение в туалете/ml/data/objects365_urls.txt
```
2) Run:
```
/Users/vaka47/Dev/Приложение в туалете/ml/scripts/download_objects365.sh \
  /Users/vaka47/Dev/Приложение в туалете/ml/data/objects365_urls.txt \
  /Users/vaka47/Dev/Приложение в туалете/ml/data/objects365
```
For convenience, a full URL list is prepared in:
`/Users/vaka47/Dev/Приложение в туалете/ml/data/objects365_urls_all.txt`

After download/extract, build a toilet-only YOLO subset:
```
python3 /Users/vaka47/Dev/Приложение в туалете/ml/scripts/build_objects365_toilet_yolo.py \
  --annotations /Users/vaka47/Dev/Приложение в туалете/ml/data/objects365/zhiyuan_objv2_train.json \
  --images-root /Users/vaka47/Dev/Приложение в туалете/ml/data/objects365 \
  --out /Users/vaka47/Dev/Приложение в туалете/ml/data/objects365_toilet \
  --split train
```

### COCO toilet subset (good for non-commercial expansion)
```
python3 /Users/vaka47/Dev/Приложение в туалете/ml/scripts/download_coco_toilet.py \
  --out /Users/vaka47/Dev/Приложение в туалете/ml/data/coco_toilet \
  --train-limit 2500 \
  --val-limit 800
```

### Merge multiple YOLO datasets into one
Example: merge your existing dataset + COCO subset:
```
python3 /Users/vaka47/Dev/Приложение в туалете/ml/scripts/merge_yolo_datasets.py \
  --out /Users/vaka47/Dev/Приложение в туалете/ml/data/dataset_merged \
  --source base=/Users/vaka47/Dev/Приложение в туалете/ml/data/dataset \
  --source coco=/Users/vaka47/Dev/Приложение в туалете/ml/data/coco_toilet
```

## Labeling format
Use **bounding boxes** around the toilet. Single class: `toilet`.

Suggested split:
- 80% train
- 10% val
- 10% test

Directory structure (YOLO format):
```
ml/data/dataset/
  images/
    train/*.jpg
    val/*.jpg
    test/*.jpg
  labels/
    train/*.txt
    val/*.txt
    test/*.txt
```
Each label file uses YOLO format: `class x_center y_center width height` (normalized 0..1).

## Dataset config
Edit `ml/data/toilet.yaml` to point to your dataset paths.

### Optional: enlarge train set with offline augmentations
If raw images are not enough yet, create an expanded dataset copy:

```
python3 /Users/vaka47/Dev/Приложение в туалете/ml/scripts/augment_yolo_dataset.py \
  --src /Users/vaka47/Dev/Приложение в туалете/ml/data/dataset \
  --out /Users/vaka47/Dev/Приложение в туалете/ml/data/dataset_aug \
  --train-copies 1
```

Then train with:
`/Users/vaka47/Dev/Приложение в туалете/ml/data/toilet_aug.yaml`

## Train
```
python3 -m pip install -r /Users/vaka47/Dev/Приложение в туалете/ml/scripts/requirements.txt
python3 /Users/vaka47/Dev/Приложение в туалете/ml/scripts/train.py \
  --data /Users/vaka47/Dev/Приложение в туалете/ml/data/toilet.yaml \
  --model yolov8n.pt \
  --epochs 80 \
  --imgsz 640
```

## Export to Core ML
```
python3 /Users/vaka47/Dev/Приложение в туалете/ml/scripts/export_coreml.py \
  --weights runs/detect/train/weights/best.pt \
  --output ToiletDetector.mlmodel
```

## Add to Xcode
Drag `ToiletDetector.mlmodel` into the Xcode target. Ensure it is included in the app bundle.

## Notes
- Start with `yolov8n` for speed on device.
- If accuracy is low, increase data quality and add more negatives.
- If false positives are white furniture or appliances, do not add a `not_toilet` class. Add them as background images with empty labels.
- You can later upgrade to `yolov8s` for better accuracy (slower).
