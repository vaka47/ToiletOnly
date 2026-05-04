from __future__ import annotations

from datetime import datetime, timezone
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, and_, or_

from ..db import get_db
from ..models import Like, Match, MatchStatus, Block, Profile, Pass, DeviceToken, Message, User
from ..schemas import LikeRequest, MatchOut, IncomingLikeOut
from ..security import get_current_user_id
from ..services.apns import send_push
from ..services.analytics import track_event
from ..services.match_policy import ensure_participant_states, apply_status_from_states, find_match_between, build_match_out

router = APIRouter(prefix="/likes", tags=["likes"])

DAILY_SUPERLIKE_LIMIT = 5


@router.get("/incoming", response_model=list[IncomingLikeOut])
async def incoming_likes(
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
):
    now = datetime.now(timezone.utc)
    pass_exists = (
        select(Pass)
        .where(and_(Pass.from_user_id == user_id, Pass.to_user_id == Like.from_user_id))
        .exists()
    )
    rows = (
        await db.execute(
            select(Like, User, Profile)
            .join(User, User.id == Like.from_user_id)
            .join(Profile, Profile.user_id == Like.from_user_id)
            .where(Like.to_user_id == user_id)
            .where(~pass_exists)
            .order_by(Like.created_at.desc())
        )
    ).all()
    items: list[IncomingLikeOut] = []
    for like, actor_user, actor_profile in rows:
        blocked = await db.execute(
            select(Block).where(
                or_(
                    and_(Block.blocker_id == user_id, Block.blocked_user_id == actor_user.id),
                    and_(Block.blocker_id == actor_user.id, Block.blocked_user_id == user_id),
                )
            )
        )
        if blocked.scalar_one_or_none():
            continue
        mutual = await db.execute(
            select(Like).where(
                and_(Like.from_user_id == user_id, Like.to_user_id == actor_user.id)
            )
        )
        if mutual.scalar_one_or_none():
            continue
        existing_match = await find_match_between(db, user_id, actor_user.id)
        if existing_match and existing_match.status != MatchStatus.expired:
            continue
        is_online = bool(
            actor_profile.is_online_toilet
            and actor_profile.session_expires_at
            and actor_profile.session_expires_at > now
        )
        items.append(
            IncomingLikeOut(
                id=f"{like.from_user_id}:{like.to_user_id}",
                from_user_id=str(actor_user.id),
                display_name=actor_user.display_name,
                age=actor_user.age,
                hide_age=bool(actor_user.hide_age),
                gender=actor_user.gender,
                toilet_selfie_url=actor_profile.toilet_selfie_url,
                photos=actor_profile.photos,
                bio_ai=actor_profile.bio_ai,
                bio_text=actor_profile.bio_text,
                interests=actor_profile.interests,
                session_video_url=actor_profile.session_video_url,
                is_online_toilet=is_online,
                session_expires_at=actor_profile.session_expires_at.isoformat() if actor_profile.session_expires_at else None,
                like_type=like.like_type,
                message=like.intro_message,
                created_at=like.created_at.isoformat(),
            )
        )
    return items


@router.post("", response_model=Optional[MatchOut])
async def like_user(
    payload: LikeRequest,
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
):
    blocked = await db.execute(
        select(Block).where(
            or_(
                and_(Block.blocker_id == user_id, Block.blocked_user_id == payload.to_user_id),
                and_(Block.blocker_id == payload.to_user_id, Block.blocked_user_id == user_id),
            )
        )
    )
    if blocked.scalar_one_or_none():
        return None

    if payload.action == "pass":
        db.add(Pass(from_user_id=user_id, to_user_id=payload.to_user_id))
        await track_event(
            db,
            event_name="pass_sent",
            user_id=user_id,
            target_user_id=payload.to_user_id,
            source="server",
            properties={},
        )
        await db.commit()
        return None

    if payload.action == "superlike":
        result_profile = await db.execute(select(Profile).where(Profile.user_id == user_id))
        profile = result_profile.scalar_one_or_none()
        if profile is None:
            raise HTTPException(status_code=404, detail="profile_not_found")
        if not profile.is_online_toilet:
            raise HTTPException(status_code=400, detail="superlike_requires_active_session")
        if profile.superlike_used_in_session:
            raise HTTPException(status_code=400, detail="superlike_limit_reached")
        now = datetime.now(timezone.utc)
        window_start = profile.superlike_daily_reset_at
        if window_start is None or window_start.date() != now.date():
            profile.superlike_daily_reset_at = now
            profile.superlike_daily_count = 0
        if profile.superlike_daily_count >= DAILY_SUPERLIKE_LIMIT:
            raise HTTPException(status_code=400, detail="superlike_daily_limit_reached")
        profile.superlike_used_in_session = True
        profile.superlike_daily_count += 1
        db.add(profile)

    like = Like(
        from_user_id=user_id,
        to_user_id=payload.to_user_id,
        like_type=payload.action,
        intro_message=payload.message.strip() if payload.message else None,
    )
    await db.merge(like)
    await track_event(
        db,
        event_name="superlike_sent" if payload.action == "superlike" else "like_sent",
        user_id=user_id,
        target_user_id=payload.to_user_id,
        source="server",
        properties={"has_message": bool(payload.message and payload.message.strip())},
    )
    await db.commit()

    tokens_result = await db.execute(select(DeviceToken).where(DeviceToken.user_id == payload.to_user_id))
    tokens = tokens_result.scalars().all()
    push_title = "Тебя лайкнули"
    push_body = "Открой Toilet Dating и посмотри, кто это."
    push_type = "like"
    if payload.action == "superlike":
        push_title = "Тебе поставили суперлайк"
        push_body = payload.message.strip() if payload.message else "Открой Toilet Dating и проверь мэтч."
        push_type = "superlike"
    for token in tokens:
        await send_push(
            device_token=token.token,
            title=push_title,
            body=push_body,
            data={"type": push_type, "from_user_id": str(user_id)},
        )

    result = await db.execute(
        select(Like).where(
            and_(
                Like.from_user_id == payload.to_user_id,
                Like.to_user_id == user_id,
            )
        )
    )
    mutual = result.scalar_one_or_none()
    if not mutual:
        return None

    existing_match = await find_match_between(db, user_id, payload.to_user_id)
    if existing_match and existing_match.status != MatchStatus.expired:
        states = await ensure_participant_states(db, existing_match)
        await apply_status_from_states(db, existing_match, states)
        await track_event(
            db,
            event_name="match_created",
            user_id=user_id,
            target_user_id=payload.to_user_id,
            match_id=str(existing_match.id),
            source="server",
            properties={"existing": True},
        )
        await db.commit()
        await db.refresh(existing_match)
        return MatchOut(**build_match_out(existing_match, states, user_id))

    match = Match(user_a_id=user_id, user_b_id=payload.to_user_id, status=MatchStatus.pending)
    db.add(match)
    await db.flush()
    states = await ensure_participant_states(db, match)
    await apply_status_from_states(db, match, states)
    intro_candidates = [like, mutual]
    for intro in intro_candidates:
        if intro and intro.like_type == "superlike" and intro.intro_message:
            db.add(Message(match_id=match.id, sender_id=intro.from_user_id, text=intro.intro_message))
    await track_event(
        db,
        event_name="match_created",
        user_id=user_id,
        target_user_id=payload.to_user_id,
        match_id=str(match.id),
        source="server",
        properties={"existing": False},
    )
    await db.commit()
    await db.refresh(match)
    return MatchOut(**build_match_out(match, states, user_id))
