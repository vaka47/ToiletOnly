# Hi-Fidelity Screen Specs

Reference frame: iPhone 15 Pro (`393 x 852`), 3x scale.

## Global Layout Rules

- Horizontal safe padding: `16`.
- Vertical rhythm base: `8`.
- Primary section gaps: `18-24`.
- Top chrome height target: `64`.
- Bottom nav container height target: `78`.

## S01 - Unlock Intro

- Hero block top margin: `96`.
- Title style: `h1`.
- Body max width: `320`.
- CTA group anchored at bottom with `32` bottom inset.
- Secondary explanatory card uses `Card/Glass`.

## S02 - Live Scanner

- Camera full bleed.
- Top capsule:
  - horizontal inset `20`,
  - top inset `54`,
  - height `44`.
- Bottom scanner card:
  - horizontal inset `18`,
  - corner radius `30`,
  - bottom inset `26`.
- Progress bar:
  - height `9`,
  - active fill gradient `brand/secondary`.
- Recovery hints row:
  - icon + short text chips (max 2 lines each).

## S03 - Auth

- Vertical alignment: centered stack with optical bias upward (`-24`).
- Apple button height `52`.
- Error text appears below CTAs, no layout jump (reserve `20` height).

## S04 - Feed Home

- Header block:
  - top padding `8`,
  - title `h2`,
  - subtitle `body`.
- Hero card:
  - target height `690`,
  - corner radius `34`,
  - shadow `floating`.
- Action row:
  - skip `68`,
  - superlike `78`,
  - like `68`.
- Quick chats strip starts `18` below card.

## S05 - Profile Expanded Panel

- Panel max height `420`.
- Internal padding `18`.
- Section title style `micro`.
- Tags flow 3 per row max.

## S06 - Chats List

- Each chat card min height `86`.
- Left avatar `52`.
- Keep state chip aligned top-right.
- Unread count badge attached to title row.

## S07 - Chat Room

- Message bubbles:
  - own bubble max width `72%`,
  - other bubble max width `76%`.
- Composer bar sticky bottom with `12` vertical internal padding.
- Keep banner appears after message 5 or on first open for pending state.

## S08 - Video Grid

- 2-column grid with `12` gap.
- Card height `274`.
- Header filters chips scroll horizontally.
- Floating create button offset:
  - right `22`,
  - bottom `106`.

## S09 - Fullscreen Reel

- Top identity row top inset `14`.
- Side rail button size `54`.
- Bottom action area bottom inset `28`.
- Caption collapsed to 3 lines by default.

## S10 - Profile Setup

- Three cards:
  1) Basics,
  2) Description,
  3) Photos.
- Save CTA sticky when keyboard hidden; in-keyboard state moves above keyboard.
- Selfie card shows session lock icon if closed.

## S11 - Activity

- Event rows with icon, title, context, timestamp.
- Group by "Now", "Today", "Earlier".

## S12 - Safety Flow

- Report reason selector first.
- Text detail second.
- Confirmation screen with short SLA promise and close CTA.
