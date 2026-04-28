# Component System (Premium v1)

## Core primitives

- `Color/Background/*`
- `Color/Text/*`
- `Type/*`
- `Radius/*`
- `Spacing/*`
- `Effect/Shadow/*`
- `Effect/Blur/*`

## Navigation

### `TopChromeBar`
- Variants: `session-active`, `session-idle`.
- Slots: title, countdown, action icons, badge.

### `BottomNav`
- Variants per active tab.
- Badge style supports 1-2 digits.

## Buttons

### `Button/Primary`
- Sizes: `md`, `lg`.
- States: default, pressed, disabled, loading.
- Fill: brand gradient.

### `Button/Secondary`
- Glass background with soft stroke.

### `Button/IconRound`
- 42 and 54 sizes.
- Optional badge.

## Pills and chips

### `SessionPill`
- Variants: active, warning, expired.

### `Tag/Interest`
- Variants: neutral, accent, selected.

### `Badge/Count`
- Auto width, caps at `99+`.

## Cards

### `Card/Glass`
- Standard panel container.

### `Card/ProfileHero`
- Media background.
- Bottom gradient fade.
- Overlays and action row slots.

### `Card/VideoGrid`
- Media + metadata + countdown.

## Inputs

### `Input/TextField`
- States: idle, focus, success, error.

### `Input/TextArea`
- Counter support.

### `Input/Segmented`
- 2 to 4 options.

### `Input/SliderDual`
- Age range pattern.

## Overlays

### `Sheet/Composer`
- Header, content, sticky CTA.

### `Dialog/Confirmation`
- Icon + text + 2 CTAs.

## Empty states

### `Empty/Feed`
### `Empty/Video`
### `Empty/Activity`

All include:
- Illustration token,
- title,
- explanatory copy,
- one clear primary action.
