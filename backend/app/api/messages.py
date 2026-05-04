from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, and_, or_
from ..db import get_db
from ..models import Match, Message, Block, MatchStatus
from ..schemas import MessageCreate, MessageOut
from ..security import get_current_user_id
from ..services.analytics import track_event
from ..services.match_policy import ensure_participant_states, apply_status_from_states

router = APIRouter(prefix="/matches", tags=["messages"])


@router.get("/{match_id}/messages", response_model=list[MessageOut])
async def get_messages(
    match_id: str,
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
):
    result = await db.execute(select(Match).where(Match.id == match_id))
    match = result.scalar_one_or_none()
    if not match:
        raise HTTPException(status_code=404, detail="match_not_found")
    if str(match.user_a_id) != user_id and str(match.user_b_id) != user_id:
        raise HTTPException(status_code=403, detail="forbidden")

    blocked = await db.execute(
        select(Block).where(
            or_(
                and_(Block.blocker_id == match.user_a_id, Block.blocked_user_id == match.user_b_id),
                and_(Block.blocker_id == match.user_b_id, Block.blocked_user_id == match.user_a_id),
            )
        )
    )
    if blocked.scalar_one_or_none():
        raise HTTPException(status_code=403, detail="blocked")

    states = await ensure_participant_states(db, match)
    status = await apply_status_from_states(db, match, states)
    if status == MatchStatus.expired:
        await db.commit()
        raise HTTPException(status_code=410, detail="match_expired")

    rows = await db.execute(
        select(Message).where(Message.match_id == match_id).order_by(Message.created_at.asc())
    )
    items = rows.scalars().all()
    return [
        MessageOut(
            id=str(item.id),
            match_id=str(item.match_id),
            sender_id=str(item.sender_id),
            text=item.text,
            created_at=item.created_at.isoformat(),
        )
        for item in items
    ]


@router.post("/{match_id}/messages", response_model=MessageOut)
async def post_message(
    match_id: str,
    payload: MessageCreate,
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
):
    result = await db.execute(select(Match).where(Match.id == match_id))
    match = result.scalar_one_or_none()
    if not match:
        raise HTTPException(status_code=404, detail="match_not_found")
    if str(match.user_a_id) != user_id and str(match.user_b_id) != user_id:
        raise HTTPException(status_code=403, detail="forbidden")

    blocked = await db.execute(
        select(Block).where(
            or_(
                and_(Block.blocker_id == match.user_a_id, Block.blocked_user_id == match.user_b_id),
                and_(Block.blocker_id == match.user_b_id, Block.blocked_user_id == match.user_a_id),
            )
        )
    )
    if blocked.scalar_one_or_none():
        raise HTTPException(status_code=403, detail="blocked")

    states = await ensure_participant_states(db, match)
    status = await apply_status_from_states(db, match, states)
    if status == MatchStatus.expired:
        await db.commit()
        raise HTTPException(status_code=410, detail="match_expired")

    message = Message(match_id=match_id, sender_id=user_id, text=payload.text)
    db.add(message)
    await track_event(
        db,
        event_name="message_sent",
        user_id=user_id,
        match_id=match_id,
        source="server",
        properties={"length": len(payload.text)},
    )
    await db.commit()
    await db.refresh(message)
    return MessageOut(
        id=str(message.id),
        match_id=str(message.match_id),
        sender_id=str(message.sender_id),
        text=message.text,
        created_at=message.created_at.isoformat(),
    )
