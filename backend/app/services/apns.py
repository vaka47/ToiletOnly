from __future__ import annotations

import time
from typing import Any, Optional
import httpx
from jose import jwt
from ..config import settings

_cached_jwt: Optional[str] = None
_cached_jwt_expires_at: int = 0


def _load_private_key() -> str:
    key = settings.apns_private_key
    if not key:
        return ""
    return key.replace("\\n", "\n")


def build_apns_jwt() -> Optional[str]:
    global _cached_jwt, _cached_jwt_expires_at
    if not settings.apns_key_id or not settings.apns_team_id:
        return None
    private_key = _load_private_key()
    if not private_key:
        return None
    now = int(time.time())
    if _cached_jwt and now < _cached_jwt_expires_at:
        return _cached_jwt
    headers = {"alg": "ES256", "kid": settings.apns_key_id}
    claims = {"iss": settings.apns_team_id, "iat": now}
    _cached_jwt = jwt.encode(claims, private_key, algorithm="ES256", headers=headers)
    _cached_jwt_expires_at = now + 45 * 60
    return _cached_jwt


def apns_host() -> str:
    return "https://api.sandbox.push.apple.com" if settings.apns_use_sandbox else "https://api.push.apple.com"


def build_payload(title: str, body: str, data: Optional[dict[str, Any]] = None) -> dict[str, Any]:
    payload = {
        "aps": {
            "alert": {"title": title, "body": body},
            "sound": "default",
            "badge": 1,
        }
    }
    if data:
        payload.update(data)
    return payload


async def send_push(device_token: str, title: str, body: str, data: Optional[dict[str, Any]] = None) -> bool:
    jwt_token = build_apns_jwt()
    if not jwt_token:
        return False
    url = f"{apns_host()}/3/device/{device_token}"
    headers = {
        "authorization": f"bearer {jwt_token}",
        "apns-topic": settings.apns_bundle_id,
        "apns-push-type": "alert",
    }
    payload = build_payload(title, body, data)
    async with httpx.AsyncClient(timeout=10) as client:
        response = await client.post(url, json=payload, headers=headers)
    return response.status_code == 200
