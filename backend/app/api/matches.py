from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from datetime import datetime, timezone

from sqlalchemy import select, and_, or_
from ..db import get_db
from ..models import Match, Block, User, Profile, Message, MatchParticipantState, Like, Pass
from ..schemas import MatchKeepRequest, MatchOut, MatchListItemOut
from ..security import get_current_user_id
from ..services.match_policy import ensure_participant_states, apply_status_from_states, build_match_out

router = APIRouter(prefix="/matches", tags=["matches"])


@router.get("/list", response_model=list[MatchListItemOut])
async def list_matches(
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
):
    now = datetime.now(timezone.utc)
    rows = (
        await db.execute(
            select(Match)
            .where(or_(Match.user_a_id == user_id, Match.user_b_id == user_id))
            .order_by(Match.created_at.desc())
        )
    ).scalars().all()
    items: list[MatchListItemOut] = []
    for match in rows:
        other_user_id = match.user_b_id if str(match.user_a_id) == user_id else match.user_a_id
        blocked = await db.execute(
            select(Block).where(
                or_(
                    and_(Block.blocker_id == match.user_a_id, Block.blocked_user_id == match.user_b_id),
                    and_(Block.blocker_id == match.user_b_id, Block.blocked_user_id == match.user_a_id),
                )
            )
        )
        if blocked.scalar_one_or_none():
            continue
        states = await ensure_participant_states(db, match)
        await apply_status_from_states(db, match, states)
        user_row = (await db.execute(select(User).where(User.id == other_user_id))).scalar_one_or_none()
        profile_row = (await db.execute(select(Profile).where(Profile.user_id == other_user_id))).scalar_one_or_none()
        if user_row is None or profile_row is None:
            continue
        latest_message = (
            await db.execute(
                select(Message)
                .where(Message.match_id == match.id)
                .order_by(Message.created_at.desc())
                .limit(1)
            )
        ).scalar_one_or_none()
        match_payload = build_match_out(match, states, user_id)
        is_online = bool(
            profile_row.is_online_toilet
            and profile_row.session_expires_at
            and profile_row.session_expires_at > now
        )
        items.append(
            MatchListItemOut(
                id=match_payload["id"],
                status=match_payload["status"],
                my_is_kept=match_payload["my_is_kept"],
                other_is_kept=match_payload["other_is_kept"],
                my_sessions_left=match_payload["my_sessions_left"],
                other_sessions_left=match_payload["other_sessions_left"],
                other_user_id=str(other_user_id),
                display_name=user_row.display_name,
                age=user_row.age,
                hide_age=bool(user_row.hide_age),
                gender=user_row.gender,
                toilet_selfie_url=profile_row.toilet_selfie_url,
                is_online_toilet=is_online,
                session_expires_at=profile_row.session_expires_at.isoformat() if profile_row.session_expires_at else None,
                last_message=latest_message.text if latest_message else None,
                last_message_at=latest_message.created_at.isoformat() if latest_message else None,
            )
        )
    await db.commit()
    items.sort(key=lambda item: item.last_message_at or item.session_expires_at or "", reverse=True)
    return items


@router.post("/keep", response_model=MatchOut)
async def keep_match(
    payload: MatchKeepRequest,
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
):
    result = await db.execute(select(Match).where(Match.id == payload.match_id))
    match = result.scalar_one_or_none()
    if not match:
        raise HTTPException(status_code=404, detail="match_not_found")
    if str(match.user_a_id) != user_id and str(match.user_b_id) != user_id:
        raise HTTPException(status_code=403, detail="forbidden")
    block_check = await db.execute(
        select(Block).where(
            or_(
                and_(Block.blocker_id == match.user_a_id, Block.blocked_user_id == match.user_b_id),
                and_(Block.blocker_id == match.user_b_id, Block.blocked_user_id == match.user_a_id),
            )
        )
    )
    if block_check.scalar_one_or_none():
        raise HTTPException(status_code=403, detail="blocked")
    states = await ensure_participant_states(db, match)
    state = next((item for item in states if str(item.user_id) == user_id), None)
    if state is None:
        raise HTTPException(status_code=500, detail="match_state_error")
    state.is_kept = True
    db.add(state)

    await apply_status_from_states(db, match, states)
    await db.commit()
    await db.refresh(match)
    return MatchOut(**build_match_out(match, states, user_id))


@router.get("/{match_id}", response_model=MatchOut)
async def get_match(
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
    block_check = await db.execute(
        select(Block).where(
            or_(
                and_(Block.blocker_id == match.user_a_id, Block.blocked_user_id == match.user_b_id),
                and_(Block.blocker_id == match.user_b_id, Block.blocked_user_id == match.user_a_id),
            )
        )
    )
    if block_check.scalar_one_or_none():
        raise HTTPException(status_code=403, detail="blocked")
    states = await ensure_participant_states(db, match)
    await apply_status_from_states(db, match, states)
    await db.commit()
    await db.refresh(match)
    return MatchOut(**build_match_out(match, states, user_id))


@router.delete("/{match_id}")
async def delete_match(
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

    related_messages = (
        await db.execute(select(Message).where(Message.match_id == match.id))
    ).scalars().all()
    for item in related_messages:
        await db.delete(item)

    participant_states = (
        await db.execute(select(MatchParticipantState).where(MatchParticipantState.match_id == match.id))
    ).scalars().all()
    for item in participant_states:
        await db.delete(item)

    related_likes = (
        await db.execute(
            select(Like).where(
                or_(
                    and_(Like.from_user_id == match.user_a_id, Like.to_user_id == match.user_b_id),
                    and_(Like.from_user_id == match.user_b_id, Like.to_user_id == match.user_a_id),
                )
            )
        )
    ).scalars().all()
    for item in related_likes:
        await db.delete(item)

    related_passes = (
        await db.execute(
            select(Pass).where(
                or_(
                    and_(Pass.from_user_id == match.user_a_id, Pass.to_user_id == match.user_b_id),
                    and_(Pass.from_user_id == match.user_b_id, Pass.to_user_id == match.user_a_id),
                )
            )
        )
    ).scalars().all()
    for item in related_passes:
        await db.delete(item)

    await db.delete(match)
    await db.commit()
    return {"ok": True}
