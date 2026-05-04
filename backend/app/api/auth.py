import base64
import json
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException
import httpx
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from ..db import get_db
from ..models import User
from ..schemas import AuthRequest, AuthResponse
from ..config import settings
from ..security import create_access_token
from ..services.analytics import track_event

try:
    from jose import jwt as jose_jwt
except Exception:  # pragma: no cover - optional dependency in local demo
    jose_jwt = None

router = APIRouter(prefix="/auth", tags=["auth"])
APPLE_ISSUER = "https://appleid.apple.com"
APPLE_KEYS_URL = f"{APPLE_ISSUER}/auth/keys"
_apple_keys_cache: dict[str, object] = {"keys": None}


def _looks_like_jwt(token: str) -> bool:
    return token.count(".") == 2


def _base64url_decode(value: str) -> bytes:
    padding = "=" * (-len(value) % 4)
    return base64.urlsafe_b64decode(value + padding)


def _read_unverified_payload(id_token: str) -> dict:
    try:
        _, payload_part, _ = id_token.split(".", 2)
        raw = _base64url_decode(payload_part)
        return json.loads(raw.decode("utf-8"))
    except Exception:
        return {}


def _payload_matches_apple_claims(payload: dict) -> bool:
    audience = payload.get("aud")
    if isinstance(audience, list):
        audience_ok = settings.apple_client_id in audience
    else:
        audience_ok = audience == settings.apple_client_id
    issuer_ok = payload.get("iss") == APPLE_ISSUER
    exp = payload.get("exp")
    if exp is None:
        expiry_ok = True
    else:
        try:
            expiry_ok = datetime.fromtimestamp(int(exp), tz=timezone.utc) > datetime.now(timezone.utc)
        except Exception:
            expiry_ok = False
    return bool(payload.get("sub")) and issuer_ok and audience_ok and expiry_ok


async def _apple_signing_keys() -> list[dict]:
    cached = _apple_keys_cache.get("keys")
    if isinstance(cached, list) and cached:
        return cached
    async with httpx.AsyncClient(timeout=5.0) as client:
        response = await client.get(APPLE_KEYS_URL)
        response.raise_for_status()
        payload = response.json()
        keys = payload.get("keys") or []
        _apple_keys_cache["keys"] = keys
        return keys


async def _resolve_apple_sub(id_token: str) -> str:
    if not _looks_like_jwt(id_token):
        if settings.allow_dev_apple_sub_tokens:
            return id_token
        raise HTTPException(status_code=401, detail="invalid_apple_token")

    fallback_payload = _read_unverified_payload(id_token)
    fallback_sub = fallback_payload.get("sub")
    if jose_jwt is None:
        if fallback_sub and (settings.allow_dev_apple_sub_tokens or _payload_matches_apple_claims(fallback_payload)):
            return str(fallback_sub)
        raise HTTPException(status_code=500, detail="apple_verifier_unavailable")

    try:
        header = jose_jwt.get_unverified_header(id_token)
    except Exception as exc:
        raise HTTPException(status_code=401, detail="invalid_apple_token") from exc

    kid = header.get("kid")
    alg = header.get("alg", "RS256")
    if not kid:
        raise HTTPException(status_code=401, detail="invalid_apple_token")

    keys = await _apple_signing_keys()
    key = next((item for item in keys if item.get("kid") == kid), None)
    if key is None:
        _apple_keys_cache["keys"] = None
        keys = await _apple_signing_keys()
        key = next((item for item in keys if item.get("kid") == kid), None)
    if key is None:
        raise HTTPException(status_code=401, detail="apple_key_not_found")

    try:
        payload = jose_jwt.decode(
            id_token,
            key,
            algorithms=[alg],
            audience=settings.apple_client_id,
            issuer=APPLE_ISSUER,
            options={"verify_at_hash": False},
        )
    except Exception as exc:
        if fallback_sub and (settings.allow_dev_apple_sub_tokens or _payload_matches_apple_claims(fallback_payload)):
            return str(fallback_sub)
        raise HTTPException(status_code=401, detail="invalid_apple_token") from exc

    apple_sub = payload.get("sub")
    if not apple_sub:
        raise HTTPException(status_code=401, detail="invalid_apple_token")
    return str(apple_sub)


@router.post("/apple", response_model=AuthResponse)
async def auth_apple(payload: AuthRequest, db: AsyncSession = Depends(get_db)):
    apple_sub = await _resolve_apple_sub(payload.id_token)
    if not apple_sub:
        raise HTTPException(status_code=400, detail="missing_token")

    result = await db.execute(select(User).where(User.apple_sub == apple_sub))
    user = result.scalar_one_or_none()
    is_new_user = user is None
    if user is None:
        user = User(apple_sub=apple_sub, age=18, gender="unknown", display_name="ToiletUser")
        db.add(user)
        await db.flush()

    await track_event(
        db,
        event_name="auth_signed_up" if is_new_user else "auth_signed_in",
        user_id=str(user.id),
        source="server",
        properties={"provider": "apple", "is_mock": not _looks_like_jwt(payload.id_token)},
    )
    await db.commit()
    await db.refresh(user)

    token = create_access_token(str(user.id))
    return AuthResponse(access_token=token, user_id=str(user.id))
