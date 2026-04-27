# ToiletOnly Backend (FastAPI)

## Run (dev)
```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt

export DATABASE_URL="postgresql+asyncpg://app:app@localhost:5432/toiletonly"
export REDIS_URL="redis://localhost:6379/0"
export JWT_SECRET="dev-secret"

uvicorn app.main:app --reload
```

## WebSocket endpoints
- `/ws/dialog` (AI dialog stream stub)
- `/ws/chat/{match_id}`
- `/ws/presence`

## Notes
- Apple auth verification is TODO in `app/api/auth.py`.
- AI dialog streaming is a stub in `app/services/ai_dialog.py`.
- Profile setup supports up to 10 additional photos (`photos`).
- Session lifecycle endpoint: `POST /profiles/session-state` with `{ "active": true|false }`.
- Match dialog lifecycle is server-side:
  - each participant has 2 active sessions to keep the match,
  - `POST /matches/keep` marks keep for current user,
  - if sessions are exhausted and keep is not confirmed, match status becomes `expired`.
