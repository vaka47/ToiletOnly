# Toilet Model A/B Test

## Purpose

Compare ready-made public toilet models against the current local `v6` model on the same scenes.

## Candidate Models

- Local baseline: `toilet_v6_from_v5_hardneg`
- Public model B: `https://universe.roboflow.com/gyanmachine/toilet-ydj8f-e8yca/model/1`
- Public model C: `https://universe.roboflow.com/tu-dellft/toilet-ydj8f-adpoa/model/1`
- Optional extra baseline: `https://templates.roboflow.com/toilet-detection`

## How To Run

1. Use the exact scene list from `toilet_model_ab_test_template.csv`.
2. For each candidate model, run the same images through preview/inference.
3. Record:
   - top confidence
   - whether the model would have opened the app
   - short note about failure mode
4. Pick the winner only by real-scene behavior, not by website metrics.

## Pass Criteria

- Toilet scenes:
  - most toilet scenes should score high and consistently
- Negative scenes:
  - chair / fridge / cabinet / door / linen must stay low
- Stability:
  - false positives on white objects are disqualifying

## What Counts As A Win

A candidate wins only if it is better than local `v6` on both:

- toilet recall
- false positive suppression on white household objects

If it only improves one side, it is not good enough.
