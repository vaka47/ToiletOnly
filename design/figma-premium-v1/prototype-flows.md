# Prototype Flows (Figma)

## Flow A - First-Time Activation (Investor critical)

1. Splash -> Unlock Intro.
2. Unlock Intro -> Live Scanner.
3. Scanner success -> Auth.
4. Auth success -> Profile Setup (guided).
5. Save profile -> Feed card.
6. Like -> Match reveal -> Chat open.

Target: complete in under 2:30 demo time.

## Flow B - Video to Match

1. Open Videos tab.
2. Open reel fullscreen.
3. React + open profile.
4. Superlike with message.
5. Return to chats and show pending/keep state.

Target: show social graph conversion from content.

## Flow C - Trust and Safety

1. Open moderation menu in reel.
2. Report flow with reason + note.
3. Confirmation reassurance.
4. Block author.
5. Return to clean feed state.

Target: demonstrate platform safety maturity.

## Flow D - Session Expiry + Keep

1. Show session countdown near zero.
2. Expiry event state.
3. Keep prompt in match/chat.
4. Final state: kept or expired.

Target: communicate unique ephemeral mechanic clearly.

## Interaction map conventions

- `Tap`: primary navigation.
- `Drag`: profile card interactions.
- `Long press`: advanced debug/help pattern only (not in production path).
- `Overlay`: lightweight action context.

## Demo mode notes

- Build deterministic sample data screens:
  - one ideal profile,
  - one pending keep match,
  - one high-engagement video.
- Avoid random loading paths in the investor prototype.
