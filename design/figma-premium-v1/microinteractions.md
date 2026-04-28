# Motion and Microinteractions

## Motion principles

- Fast response, calm finish.
- Emphasize confidence, not playfulness.
- Every interaction should confirm state change.

## Global specs

- Tap feedback: 95% scale, 120ms down, 160ms release.
- Sheet open: translate Y 24 -> 0, fade 0 -> 1, 280ms.
- Screen push: 260ms with slight parallax.

## Unlock screen

- Confidence ring updates every frame with smoothing.
- Success transition:
  1) ring pulse,
  2) short haptic success,
  3) card morph into top session pill.

## Swipe card

- Drag threshold preview tint:
  - left = skip (neutral),
  - right = like (coral),
  - up = expand (sky).
- On commit:
  - directional flyout + haptic,
  - next card fades in with 40ms stagger.

## Video reel

- Rail buttons use subtle glow on press.
- React action bursts micro-particle effect (6 particles max).
- Caption expand animates line-height smoothly, no abrupt jump.

## Trust states

- Moderation fail states should shake input card lightly.
- Recovery hints fade in immediately after error.
- Never show blocking modal without a direct next action.
