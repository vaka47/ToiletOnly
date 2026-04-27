# Hard Negative Pack Sources

These are the recommended ready-made image packs for toilet hard negatives.

## Official sources

- Open Images V7 overview: https://storage.googleapis.com/openimages/web/index.html
- Open Images V7 download page: https://storage.googleapis.com/openimages/web/download_v7.html
- Objects365 overview: https://www.objects365.org/overview.html
- Objects365 download and license page: https://www.objects365.org/download.html

## Open Images V7 packs

Use exact class names from `/Users/vaka47/Dev/Приложение в туалете/ml/data/openimages_hard_negative_classes.txt`.

High-value classes for your false positives:

- Chair
- Stool
- Refrigerator
- Cabinetry
- Cupboard
- Closet
- Wardrobe
- Drawer
- Shelf
- Door
- Nightstand
- Table
- Countertop
- Bed
- Couch
- Towel
- Sink
- Bathtub
- Shower
- Mirror
- Washing machine
- Dishwasher
- Toilet paper
- Waste container

Why these matter:

- `Chair`, `Stool`, `Refrigerator`: direct current false positives.
- `Cabinetry`, `Door`, `Countertop`, `Wardrobe`: large white flat surfaces.
- `Towel`, `Bed`, `Couch`: soft white textures and curved forms.
- `Sink`, `Bathtub`, `Mirror`, `Washing machine`, `Dishwasher`: bathroom and kitchen context that must not unlock the app.

## Objects365 packs

Use exact class names from `/Users/vaka47/Dev/Приложение в туалете/ml/data/objects365_hard_negative_classes.txt`.

Recommended categories:

- Chair
- Stool
- Cabinet/shelf
- Refrigerator
- Bed
- Towel
- Mirror
- Sink
- Bathtub
- Nightstand
- Toilet Paper
- Washing Machine/Drying Machine
- Dishwasher
- Urinal
- Trash bin Can
- Cleaning Products
- Showerhead

Why Objects365 is useful:

- It covers many indoor household categories that visually collide with toilets.
- It is suitable as a non-commercial hard-negative source.

## Recommended strategy

1. Download Open Images class packs first.
2. Add your own negative photo and video frames from the same apartment and lighting.
3. Optionally add Objects365 background packs for extra diversity.
4. Merge all of them as background-only images with empty YOLO labels.
