# Production Release Checklist

## Must Have Before TestFlight
- Real production API base URL in iOS build settings.
- Production Postgres and Redis up, health endpoints green.
- `ALLOW_DEV_APPLE_SUB_TOKENS=false`.
- Real `JWT_SECRET`, APNS key, team id, key id, bundle id.
- Privacy Policy URL and Terms URL prepared.
- At least one moderation operator account.
- Device push registration verified on a physical iPhone.

## Device Smoke Test
1. Launch app and unlock with a real toilet.
2. Complete onboarding in both `ru` and `en`.
3. Swipe `skip / like / superlike`.
4. Create a match and send a first message.
5. Trigger `ping` and verify push delivery.
6. Record a session video with face in frame.
7. Publish the video and verify it appears in feed and profile.
8. Open video comments, like the video, report the video.
9. Block a user and verify feed/chat cleanup.
10. Let a session expire and verify forced re-entry through toilet unlock.

## Performance Gate
- Lock screen preview feels stable at `~30fps`.
- No visible stutter when pointing camera at toilet for 5-10 seconds.
- Record button starts within ~1 second after camera becomes ready.
- Session video upload does not freeze UI.
- Feed screen opens in under 2 seconds on normal Wi-Fi.

## App Store / TestFlight Gate
- Release build signed with production profile.
- Push entitlement present in release build.
- Camera, microphone, photos, location permission copy reviewed.
- Demo content looks premium in English and Russian.
- Backup demo video prepared in case live network or camera fails.
