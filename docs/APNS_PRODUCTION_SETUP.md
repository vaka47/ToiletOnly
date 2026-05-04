# APNS Production Setup

## What You Need
- Apple Developer account with access to Certificates, Identifiers & Profiles.
- App ID that matches the iOS bundle id.
- Push Notifications enabled for that App ID.

## Steps
1. In Apple Developer, create one APNS authentication key.
2. Save the downloaded `.p8` file immediately. Apple lets you download it only once.
3. Record the `Key ID` and `Team ID`.
4. Put those values into backend production secrets:
   - `APNS_KEY_ID`
   - `APNS_TEAM_ID`
   - `APNS_BUNDLE_ID`
   - `APNS_PRIVATE_KEY`
   - `APNS_USE_SANDBOX=false`
5. Install a release-signed build on a physical iPhone.
6. Launch the app, log in, and verify `/devices/register` stores the device token.
7. Trigger a real push event: like, superlike, or ping.

## Validation
- Backend `send_push` returns HTTP `200`.
- Device receives alert while app is backgrounded.
- Production build uses the same bundle id as `APNS_BUNDLE_ID`.

## Failure Cases To Check
- Wrong bundle id in backend.
- Sandbox key against production build or vice versa.
- Push capability missing in signing profile.
- User denied notifications on device.
