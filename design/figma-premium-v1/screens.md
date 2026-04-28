# Screen Blueprint (Premium)

## 1) Entry + Unlock

### 1.1 Splash
- Centered animated logomark.
- One-line value proposition.
- 900ms transition to unlock intro.

### 1.2 Unlock Intro
- Headline: why this mechanic exists.
- 3 short bullets: privacy, authenticity, instant vibe.
- CTA: `Start session`.

### 1.3 Live Scanner (Hero)
- Fullscreen camera.
- Top strip: brand, session target (`15 min`), trust badge.
- Bottom premium card:
  - live state title,
  - confidence progress,
  - fix-hints when detection fails.
- Primary behavior: no dead-end errors; always show next action.

## 2) Auth

### 2.1 Sign In
- Strong headline + trust text.
- Primary CTA: `Continue with Apple`.
- Secondary: temporary dev mode (hidden in production variant).
- Legal links inline under CTA stack.

## 3) Main Shell

### 3.1 Global Top Bar
- Left: product mark + current mode.
- Center: countdown pill with progress ring.
- Right: activity + create video.

### 3.2 Bottom Nav (4 tabs)
- Feed, Chats, Videos, Profile.
- Active tab with gradient capsule.
- Badge semantics: activity vs message vs pending keep.

## 4) Feed

### 4.1 Profile Stack
- High-impact media.
- Gesture affordances visible in onboarding only.
- Actions: skip / superlike / like.
- Instant haptic confirmation.

### 4.2 Expanded Profile
- Story block, interests, distance, session state.
- Past videos carousel.
- Trust layer: verification and report access.

### 4.3 Empty Feed
- Soft premium illustration.
- Practical next step CTA: widen radius / retry in 3 min.

## 5) Match + Chat

### 5.1 Active Chats Strip
- Horizontal high-priority cards.
- Keep-state status chip.

### 5.2 Chat Room
- Message grouping.
- Inline keep prompts.
- Session countdown context always visible.

## 6) Video

### 6.1 Video Grid
- 2-column masonry style.
- Session chips on each card.
- Lightweight filters accessible from top-right.

### 6.2 Fullscreen Reel
- Creator identity and session state above fold.
- Right rail: react/comment/more.
- Bottom: caption + match actions.
- Fast report/block/hide flow.

### 6.3 Comments
- Sheet with threaded replies.
- Locked state explanatory placeholder.

## 7) Profile Setup

### 7.1 Basics
- Name, age, gender, targeting.

### 7.2 Persona
- Tone, bio, interests.

### 7.3 Media
- Toilet selfie requirement with explicit rationale.
- Additional photos with quality checklist.

## 8) Safety + Trust

### 8.1 Report Flow
- Reason categories first.
- Optional free text second.
- Confirmation state with SLA copy.

### 8.2 Blocked Users
- Search + unblock patterns.
- Clear explanatory microcopy.

## 9) Investor Demo Prototype Flow

1. Unlock success in under 7 seconds.
2. Complete profile in guided mode.
3. Swipe to match and open chat.
4. Open video, react, and superlike.
5. Show safety/report confidence quickly.
