from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, and_, or_
from ..db import get_db
from ..models import DeviceToken, Ping, Block, MatchStatus
from ..schemas import PingRequest
from ..security import get_current_user_id
from ..services.apns import send_push
from ..services.match_policy import find_match_between, ensure_participant_states, apply_status_from_states

router = APIRouter(prefix="/ping", tags=["ping"])


@router.post("")
async def send_ping(
    payload: PingRequest,
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
):
    blocked = await db.execute(
        select(Block).where(
            or_(
                and_(Block.blocker_id == user_id, Block.blocked_user_id == payload.target_user_id),
                and_(Block.blocker_id == payload.target_user_id, Block.blocked_user_id == user_id),
            )
        )
    )
    if blocked.scalar_one_or_none():
        raise HTTPException(status_code=403, detail="blocked")

    match = await find_match_between(db, user_id, payload.target_user_id)
    match_id = None
    if match:
        states = await ensure_participant_states(db, match)
        status = await apply_status_from_states(db, match, states)
        if status != MatchStatus.expired:
            match_id = str(match.id)

    ping = Ping(sender_id=user_id, target_user_id=payload.target_user_id, message=payload.message)
    db.add(ping)
    await db.commit()

    tokens_result = await db.execute(
        select(DeviceToken).where(DeviceToken.user_id == payload.target_user_id)
    )
    tokens = tokens_result.scalars().all()

    sent = 0
    for token in tokens:
        ok = await send_push(
            device_token=token.token,
            title="Тебя зовут в туалет",
            body=payload.message or "Зайди в Toilet Dating",
            data={"type": "ping", "from_user_id": str(user_id), "match_id": match_id},
        )
        if ok:
            sent += 1

    return {"status": "sent", "targets": len(tokens), "sent": sent}
