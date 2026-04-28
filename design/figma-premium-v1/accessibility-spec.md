# Accessibility Spec (A11y)

## Contrast

- Body text minimum contrast: `4.5:1`.
- Large text minimum contrast: `3:1`.
- Icon-only interactive controls: `3:1` against background.
- Do not place secondary text on dynamic media without overlay.

## Typography and scaling

- Support Dynamic Type from `Small` to `AX2`.
- Titles wrap to 2 lines max on narrow width.
- Critical CTAs must not truncate at `AX2`.

## Touch targets

- Minimum interactive target: `44 x 44`.
- Side rail controls in reel remain `>= 54`.
- Chips must maintain tap area even when visually compact.

## Motion sensitivity

- Respect reduced motion setting.
- Replace transform-heavy transitions with crossfades in reduced mode.
- Disable particle bursts in reduced mode.

## VoiceOver

- Meaningful labels for:
  - countdown pill (`Session time remaining`),
  - keep state chips,
  - moderation actions.
- Group profile card elements for linear reading.
- Announce unlock success immediately.

## Input and errors

- Error messages are actionable, never vague.
- For moderation fails, provide explicit correction instructions.
- Preserve user-entered text after validation failure.

## Localization

- RU and EN support with no clipped controls.
- Avoid culturally ambiguous idioms in critical trust/safety copy.
