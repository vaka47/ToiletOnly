from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Optional

from fastapi import APIRouter, Depends, Query
from sqlalchemy import and_, func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from ..db import get_db
from ..models import Block, InboxState, Like, Match, MatchStatus, Ping, Profile, User, Video, VideoComment, VideoReaction
from ..schemas import ActivityItemOut, InboxReadRequest, InboxSummaryOut
from ..security import get_current_user_id
from ..services.match_policy import find_match_between

router = APIRouter(prefix="/activity", tags=["activity"])


@dataclass
class _EventEnvelope:
    item: ActivityItemOut
    created_at: datetime


async def _ensure_inbox_state(db: AsyncSession, user_id: str) -> InboxState:
    state = (await db.execute(select(InboxState).where(InboxState.user_id == user_id))).scalar_one_or_none()
    if state is None:
        state = InboxState(user_id=user_id)
        db.add(state)
        await db.flush()
    return state


@router.get("/feed", response_model=list[ActivityItemOut])
async def activity_feed(
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
    limit: int = Query(default=50, ge=1, le=200),
):
    now = datetime.now(timezone.utc)
    blocked_rows = (
        await db.execute(
            select(Block).where(
                or_(Block.blocker_id == user_id, Block.blocked_user_id == user_id)
            )
        )
    ).scalars().all()
    blocked_ids = {
        str(block.blocked_user_id) if str(block.blocker_id) == user_id else str(block.blocker_id)
        for block in blocked_rows
    }
    match_cache: dict[str, Optional[str]] = {}
    events: list[_EventEnvelope] = []

    async def append_event(
        *,
        event_type: str,
        actor_user: User,
        actor_profile: Profile,
        created_at: datetime,
        message: Optional[str] = None,
        video_id: Optional[str] = None,
    ) -> None:
        actor_id = str(actor_user.id)
        if actor_id in blocked_ids:
            return
        if actor_id not in match_cache:
            match = await find_match_between(db, user_id, actor_user.id)
            match_cache[actor_id] = str(match.id) if match else None
        events.append(
            _EventEnvelope(
                item=ActivityItemOut(
                    id=f"{event_type}:{actor_id}:{created_at.isoformat()}",
                    event_type=event_type,
                    actor_user_id=actor_id,
                    actor_display_name=actor_user.display_name,
                    actor_age=actor_user.age,
                    actor_gender=actor_user.gender,
                    actor_toilet_selfie_url=actor_profile.toilet_selfie_url,
                    actor_photos=actor_profile.photos,
                    actor_bio_ai=actor_profile.bio_ai,
                    actor_bio_text=actor_profile.bio_text,
                    actor_interests=actor_profile.interests,
                    actor_session_video_url=actor_profile.session_video_url,
                    actor_is_online_toilet=bool(
                        actor_profile.is_online_toilet
                        and actor_profile.session_expires_at
                        and actor_profile.session_expires_at > now
                    ),
                    actor_session_expires_at=actor_profile.session_expires_at.isoformat()
                    if actor_profile.session_expires_at
                    else None,
                    message=message,
                    match_id=match_cache[actor_id],
                    video_id=video_id,
                    created_at=created_at.isoformat(),
                ),
                created_at=created_at,
            )
        )

    like_rows = (
        await db.execute(
            select(Like, User, Profile)
            .join(User, User.id == Like.from_user_id)
            .join(Profile, Profile.user_id == Like.from_user_id)
            .where(Like.to_user_id == user_id)
            .order_by(Like.created_at.desc())
            .limit(limit)
        )
    ).all()
    for like, actor_user, actor_profile in like_rows:
        event_type = "superlike_received" if like.like_type == "superlike" else "like_received"
        await append_event(
            event_type=event_type,
            actor_user=actor_user,
            actor_profile=actor_profile,
            created_at=like.created_at,
            message=like.intro_message,
        )

    ping_rows = (
        await db.execute(
            select(Ping, User, Profile)
            .join(User, User.id == Ping.sender_id)
            .join(Profile, Profile.user_id == Ping.sender_id)
            .where(Ping.target_user_id == user_id)
            .order_by(Ping.created_at.desc())
            .limit(limit)
        )
    ).all()
    for ping, actor_user, actor_profile in ping_rows:
        await append_event(
            event_type="ping_received",
            actor_user=actor_user,
            actor_profile=actor_profile,
            created_at=ping.created_at,
            message=ping.message,
        )

    comment_rows = (
        await db.execute(
            select(VideoComment, Video, User, Profile)
            .join(Video, Video.id == VideoComment.video_id)
            .join(User, User.id == VideoComment.user_id)
            .join(Profile, Profile.user_id == VideoComment.user_id)
            .where(
                Video.user_id == user_id,
                VideoComment.user_id != user_id,
                VideoComment.deleted_at.is_(None),
            )
            .order_by(VideoComment.created_at.desc())
            .limit(limit)
        )
    ).all()
    for comment, video, actor_user, actor_profile in comment_rows:
        await append_event(
            event_type="video_comment",
            actor_user=actor_user,
            actor_profile=actor_profile,
            created_at=comment.created_at,
            message=comment.text,
            video_id=str(video.id),
        )

    reaction_rows = (
        await db.execute(
            select(VideoReaction, Video, User, Profile)
            .join(Video, Video.id == VideoReaction.video_id)
            .join(User, User.id == VideoReaction.user_id)
            .join(Profile, Profile.user_id == VideoReaction.user_id)
            .where(Video.user_id == user_id, VideoReaction.user_id != user_id)
            .order_by(VideoReaction.created_at.desc())
            .limit(limit)
        )
    ).all()
    for reaction, video, actor_user, actor_profile in reaction_rows:
        await append_event(
            event_type="video_reaction",
            actor_user=actor_user,
            actor_profile=actor_profile,
            created_at=reaction.created_at,
            message=reaction.emoji,
            video_id=str(video.id),
        )

    events.sort(key=lambda item: item.created_at, reverse=True)
    return [item.item for item in events[:limit]]


@router.get("/summary", response_model=InboxSummaryOut)
async def activity_summary(
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
):
    now = datetime.now(timezone.utc)
    state = await _ensure_inbox_state(db, user_id)

    blocked_rows = (
        await db.execute(
            select(Block).where(
                or_(Block.blocker_id == user_id, Block.blocked_user_id == user_id)
            )
        )
    ).scalars().all()
    blocked_ids = {
        str(block.blocked_user_id) if str(block.blocker_id) == user_id else str(block.blocker_id)
        for block in blocked_rows
    }

    activity_since = state.activity_seen_at
    likes_since = state.likes_seen_at
    matches_since = state.matches_seen_at

    activity_count = 0

    like_query = select(Like, User).join(User, User.id == Like.from_user_id).where(Like.to_user_id == user_id)
    if activity_since is not None:
        like_query = like_query.where(Like.created_at > activity_since)
    like_rows = (await db.execute(like_query)).all()
    activity_count += sum(1 for _, actor_user in like_rows if str(actor_user.id) not in blocked_ids)

    ping_query = select(Ping, User).join(User, User.id == Ping.sender_id).where(Ping.target_user_id == user_id)
    if activity_since is not None:
        ping_query = ping_query.where(Ping.created_at > activity_since)
    ping_rows = (await db.execute(ping_query)).all()
    activity_count += sum(1 for _, actor_user in ping_rows if str(actor_user.id) not in blocked_ids)

    comment_query = (
        select(VideoComment, User)
        .join(Video, Video.id == VideoComment.video_id)
        .join(User, User.id == VideoComment.user_id)
        .where(
            Video.user_id == user_id,
            VideoComment.user_id != user_id,
            VideoComment.deleted_at.is_(None),
        )
    )
    if activity_since is not None:
        comment_query = comment_query.where(VideoComment.created_at > activity_since)
    comment_rows = (await db.execute(comment_query)).all()
    activity_count += sum(1 for _, actor_user in comment_rows if str(actor_user.id) not in blocked_ids)

    reaction_query = (
        select(VideoReaction, User)
        .join(Video, Video.id == VideoReaction.video_id)
        .join(User, User.id == VideoReaction.user_id)
        .where(Video.user_id == user_id, VideoReaction.user_id != user_id)
    )
    if activity_since is not None:
        reaction_query = reaction_query.where(VideoReaction.created_at > activity_since)
    reaction_rows = (await db.execute(reaction_query)).all()
    activity_count += sum(1 for _, actor_user in reaction_rows if str(actor_user.id) not in blocked_ids)

    unread_likes_count = 0
    like_list_query = (
        select(Like, User, Profile)
        .join(User, User.id == Like.from_user_id)
        .join(Profile, Profile.user_id == Like.from_user_id)
        .where(Like.to_user_id == user_id)
        .order_by(Like.created_at.desc())
    )
    if likes_since is not None:
        like_list_query = like_list_query.where(Like.created_at > likes_since)
    like_list_rows = (await db.execute(like_list_query)).all()
    for like, actor_user, _ in like_list_rows:
        actor_id = str(actor_user.id)
        if actor_id in blocked_ids:
            continue
        mutual = await db.execute(
            select(Like).where(and_(Like.from_user_id == user_id, Like.to_user_id == actor_user.id))
        )
        if mutual.scalar_one_or_none():
            continue
        existing_match = await find_match_between(db, user_id, actor_user.id)
        if existing_match and existing_match.status != MatchStatus.expired:
            continue
        unread_likes_count += 1

    unread_matches_query = select(func.count(Match.id)).where(
        or_(Match.user_a_id == user_id, Match.user_b_id == user_id),
        Match.status != MatchStatus.expired,
    )
    if matches_since is not None:
        unread_matches_query = unread_matches_query.where(Match.created_at > matches_since)
    unread_matches_count = int((await db.execute(unread_matches_query)).scalar() or 0)

    await db.commit()
    return InboxSummaryOut(
        unread_activity_count=activity_count,
        unread_likes_count=unread_likes_count,
        unread_matches_count=unread_matches_count,
    )


@router.post("/read")
async def mark_activity_read(
    payload: InboxReadRequest,
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
):
    state = await _ensure_inbox_state(db, user_id)
    now = datetime.now(timezone.utc)
    if payload.scope == "activity":
        state.activity_seen_at = now
    elif payload.scope == "likes":
        state.likes_seen_at = now
    else:
        state.matches_seen_at = now
    db.add(state)
    await db.commit()
    return {"ok": True, "scope": payload.scope}
