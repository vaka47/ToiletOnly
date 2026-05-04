# Moderation Ops Runbook

## Queue Priorities
- `P0`: child safety, threats of violence, explicit sexual content, doxxing.
- `P1`: harassment, hate speech, repeat unsolicited contact, impersonation.
- `P2`: spam, low-quality reports, minor profile abuse.

## SLA Targets
- `P0`: review within 15 minutes.
- `P1`: review within 2 hours.
- `P2`: review within 24 hours.

## Operator Flow
1. Open `Ops Dashboard`.
2. Review the report reason, object id, reporter, target user, and history.
3. Check the profile, chat, or video linked by `object_id`.
4. Mark status:
   - `reviewing`
   - `resolved`
   - `dismissed`
5. Leave a short review note.
6. If abuse is confirmed, block content visibility and suspend the account manually until automated enforcement exists.

## Escalation Rules
- Escalate repeated sexual-content reports.
- Escalate any real-world safety concern.
- Escalate coordinated harassment or fraud rings.

## Evidence Handling
- Keep report text, timestamps, user ids, and moderation notes.
- Preserve minimal necessary evidence.
- Limit staff access to sensitive media.

## Daily Review
- Open report count.
- Repeat offenders.
- Video moderation false positives / false negatives.
- Push delivery failures for critical safety notifications.
