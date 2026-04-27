from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, Query
from sqlalchemy import and_, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from ..db import get_db
from ..models import Block, Like, Ping, Profile, User, Video, VideoComment, VideoReaction
from ..schemas import ActivityItemOut
from ..security import get_current_user_id
from ..services.match_policy import find_match_between

router = APIRouter(prefix="/activity", tags=["activity"])


@dataclass
class _EventEnvelope:
    item: ActivityItemOut
    created_at: datetime


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
    match_cache: dict[str, str | None] = {}
    events: list[_EventEnvelope] = []

    async def append_event(
        *,
        event_type: str,
        actor_user: User,
        actor_profile: Profile,
        created_at: datetime,
        message: str | None = None,
        video_id: str | None = None,
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
