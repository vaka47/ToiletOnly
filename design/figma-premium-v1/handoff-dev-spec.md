# Dev Handoff Spec

## Scope

This handoff defines implementation expectations for the premium redesign.

## Build order

1. Foundations and tokens.
2. Shared components.
3. App shell (top chrome + bottom nav).
4. Unlock and auth.
5. Feed and profile card system.
6. Chat and keep states.
7. Video grid and reel.
8. Safety and edge states.

## Engineering constraints

- Keep existing product logic; redesign is visual/interaction first.
- Preserve API contracts and session mechanics.
- No new dependency required for visual parity unless justified.

## Component contract

- Every component must define:
  - sizes,
  - states,
  - empty/loading/error behavior,
  - accessibility label.

## Acceptance checklist (per screen)

- Matches layout spec on iPhone 15 Pro and iPhone 13 mini.
- No clipped text in RU/EN.
- All CTAs reachable by thumb in one-handed hold (where expected).
- Motion is smooth at 60fps target on modern devices.
- Reduced motion fallback works.

## QA states to include

- Offline mode.
- Empty feed.
- Upload moderation fail.
- Session expired.
- Pending keep / kept / expired match states.

## Metrics instrumentation suggestions

- Unlock start/success/fail reason.
- Time to first profile action.
- Video open to reaction conversion.
- Report submit success.
- Keep confirmation completion.
