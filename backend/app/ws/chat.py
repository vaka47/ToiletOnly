from __future__ import annotations

from jose import jwt
from fastapi import WebSocket
from sqlalchemy import select, and_, or_
from ..config import settings
from ..db import get_db
from ..models import Match, Block, MatchStatus
from ..services.match_policy import ensure_participant_states, apply_status_from_states


def _extract_user_id(auth_header: str | None) -> str | None:
    if not auth_header or not auth_header.lower().startswith("bearer "):
        return None
    token = auth_header.split(" ", 1)[1]
    try:
        payload = jwt.decode(
            token,
            settings.jwt_secret,
            algorithms=["HS256"],
            audience=settings.jwt_audience,
            issuer=settings.jwt_issuer,
        )
        return payload.get("sub")
    except Exception:
        return None


async def chat_socket(ws: WebSocket, match_id: str):
    await ws.accept()
    try:
        user_id = _extract_user_id(ws.headers.get("authorization"))
        if not user_id:
            await ws.close(code=1008)
            return

        async for db in get_db():
            result = await db.execute(select(Match).where(Match.id == match_id))
            match = result.scalar_one_or_none()
            if not match:
                await ws.close(code=1008)
                return
            if str(match.user_a_id) != user_id and str(match.user_b_id) != user_id:
                await ws.close(code=1008)
                return

            blocked = await db.execute(
                select(Block).where(
                    or_(
                        and_(Block.blocker_id == match.user_a_id, Block.blocked_user_id == match.user_b_id),
                        and_(Block.blocker_id == match.user_b_id, Block.blocked_user_id == match.user_a_id),
                    )
                )
            )
            if blocked.scalar_one_or_none():
                await ws.close(code=1008)
                return

            states = await ensure_participant_states(db, match)
            status = await apply_status_from_states(db, match, states)
            if status == MatchStatus.expired:
                await db.commit()
                await ws.close(code=1008)
                return
            await db.commit()
            break

        while True:
            data = await ws.receive_text()
            await ws.send_json({"match_id": match_id, "text": data})
    finally:
        await ws.close()
