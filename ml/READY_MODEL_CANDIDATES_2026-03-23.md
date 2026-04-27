# Ready Toilet Models: Shortlist

Date: 2026-03-23

## Goal

Find a ready-made toilet detector that can outperform the current local model on the user's real scenes:

- real toilet
- white chair
- refrigerator
- white cabinet / door
- towel / linen / close white surfaces

## Current Local Baseline

- Model: `toilet_v6_from_v5_hardneg`
- Weights: `/Volumes/Untitled/ToiletML/runs/toilet_v6_from_v5_hardneg/weights/best.pt`
- CoreML package: `/Users/vaka47/Dev/Приложение в туалете/ml/best_toilet_v6_from_v5_hardneg.mlpackage`
- App resource: `/Users/vaka47/Dev/Приложение в туалете/ToiletOnly/Resources/ToiletDetector.mlpackage`

Reference metrics:

- val: `P=0.920`, `R=0.837`, `mAP50=0.909`, `mAP50-95=0.767`
- test: `P=0.888`, `R=0.794`, `mAP50=0.863`, `mAP50-95=0.728`

## Shortlist

### Candidate A

- Name: Roboflow Toilet Detection Template
- URL: `https://templates.roboflow.com/toilet-detection`
- Type: ready preview / hosted workflow
- Why test it:
  - fastest possible browser check
  - no local training needed
  - useful as a "market baseline"
- Risk:
  - template metrics are not your apartment metrics
  - deployment path is less direct than your current CoreML flow

### Candidate B

- Name: GyanMachine TOILET
- Model page: `https://universe.roboflow.com/gyanmachine/toilet-ydj8f-e8yca/model/1`
- Dataset page: `https://universe.roboflow.com/gyanmachine/toilet-ydj8f-e8yca`
- Model type: YOLOv11 Object Detection (Fast)
- Reported metrics on page:
  - mAP@50: `99.2%`
  - Precision: `98.5%`
  - Recall: `98.1%`
- Why test it:
  - explicit toilet-only public model
  - browser inference available
  - iOS deployment path exists through Roboflow
- Risk:
  - public-page metrics are likely optimistic for your real negatives
  - unknown data quality and unknown negative coverage

### Candidate C

- Name: TU TOILET
- Model page: `https://universe.roboflow.com/tu-dellft/toilet-ydj8f-adpoa/model/1`
- Model type: Roboflow 3.0 Object Detection (Fast)
- Reported metrics on page:
  - mAP@50: `99.5%`
  - Precision: `99.0%`
  - Recall: `98.4%`
- Why test it:
  - another toilet-only public model
  - easy A/B against Candidate B
  - gives diversity across training origin
- Risk:
  - same as above: page metrics are not trustworthy enough on your scenes

## Deployment Paths

### Path 1: Fastest Comparison

Use Roboflow browser preview on the same fixed image set.

Expected outcome:

- keep the winner only if it clearly beats local `v6`
- reject immediately if refrigerator / chair still score like toilet

### Path 2: Fastest iPhone Prototype

If one Roboflow candidate wins on your image set, prototype it via Roboflow iOS SDK.

Docs:

- `https://docs.roboflow.com/developer/ios-sdk/using-the-ios-sdk`

This path is good for fast evaluation, not necessarily the final production architecture.

### Path 3: Keep Current App Architecture

If no public model beats `v6` clearly, keep the current CoreML app path and continue improving your own model with:

- more hard negatives
- more real toilet photos from your apartment
- scene-specific negatives from your exact lighting

## Decision Rule

A candidate is acceptable only if all of the following are true:

1. Real toilet gets stable positive scores on full-frame and angled shots.
2. White chair does not beat the toilet.
3. Refrigerator does not beat the toilet.
4. White cabinet / door / linen do not trigger unlock-like confidence repeatedly.
5. Performance is stable enough for iPhone realtime use.

If a public model wins on metrics but still confuses chair / fridge, reject it.

## Recommendation

Do not replace the current model blindly.

Run a strict A/B test first:

1. local `v6`
2. Candidate B
3. Candidate C

If neither B nor C is clearly better on your negatives, stay with `v6` and keep training your own model.
