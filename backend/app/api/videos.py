from __future__ import annotations

from datetime import datetime, timedelta, timezone
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func, and_, or_
from math import radians, sin, cos, sqrt, atan2

from ..db import get_db
from ..models import Video, VideoComment, VideoFollow, VideoReaction, User, Profile, Block
from ..schemas import FollowStatusOut, VideoOut, VideoCommentCreate, VideoCommentOut, VideoReactionCreate
from ..security import get_current_user_id

router = APIRouter(prefix="/videos", tags=["videos"])


def _distance_km(a_lat: float, a_lon: float, b_lat: float, b_lon: float) -> float:
    r = 6371.0
    dlat = radians(b_lat - a_lat)
    dlon = radians(b_lon - a_lon)
    lat1 = radians(a_lat)
    lat2 = radians(b_lat)
    h = sin(dlat / 2) ** 2 + cos(lat1) * cos(lat2) * sin(dlon / 2) ** 2
    return 2 * r * atan2(sqrt(h), sqrt(1 - h))


def _viewer_can_match_author(
    viewer_user: Optional[User],
    viewer_profile: Optional[Profile],
    author_user: User,
    author_profile: Optional[Profile],
) -> bool:
    if viewer_user is None or viewer_profile is None or author_profile is None:
        return False
    if str(viewer_user.id) == str(author_user.id):
        return False

    viewer_targets = set(viewer_profile.looking_for_genders or [])
    author_targets = set(author_profile.looking_for_genders or [])

    viewer_accepts = not viewer_targets or author_user.gender in viewer_targets
    author_accepts = not author_targets or viewer_user.gender in author_targets
    return viewer_accepts and author_accepts


def _viewer_follows_author(
    viewer_follows: set[str],
    author_user: User,
) -> bool:
    return str(author_user.id) in viewer_follows


@router.get("/feed", response_model=list[VideoOut])
async def video_feed(
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
    target_gender: Optional[str] = Query(default=None),
    age_min: Optional[int] = Query(default=None, ge=18, le=100),
    age_max: Optional[int] = Query(default=None, ge=18, le=100),
    sort_by: str = Query(default="popular", pattern="^(popular|distance|recent)$"),
    radius_km: Optional[float] = Query(default=None, ge=1, le=500),
):
    now = datetime.now(timezone.utc)
    visible_after = now - timedelta(minutes=15)
    my_profile = (await db.execute(select(Profile).where(Profile.user_id == user_id))).scalar_one_or_none()
    my_user = (await db.execute(select(User).where(User.id == user_id))).scalar_one_or_none()
    blocked_exists = (
        select(Block)
        .where(
            or_(
                and_(Block.blocker_id == user_id, Block.blocked_user_id == Video.user_id),
                and_(Block.blocker_id == Video.user_id, Block.blocked_user_id == user_id),
            )
        )
        .exists()
    )
    query = (
        select(Video, User, Profile)
        .join(User, User.id == Video.user_id)
        .join(Profile, Profile.user_id == Video.user_id)
        .where(
            Video.user_id != user_id,
            Video.comments_locked.is_(False),
            Profile.is_online_toilet.is_(True),
            Profile.session_expires_at.is_not(None),
            Profile.session_expires_at > now,
            Video.created_at >= visible_after,
            ~blocked_exists,
        )
    )
    if target_gender and target_gender in {"male", "female", "other"}:
        query = query.where(User.gender == target_gender)
    if age_min is not None:
        query = query.where(User.age >= age_min)
    if age_max is not None:
        query = query.where(User.age <= age_max)

    rows = (await db.execute(query)).all()
    if not rows:
        return []

    follows_rows = await db.execute(
        select(VideoFollow.target_user_id).where(VideoFollow.follower_id == user_id)
    )
    viewer_follows = {str(item) for item in follows_rows.scalars().all()}

    video_ids = [video.id for video, _, _ in rows]
    comments_rows = await db.execute(
        select(VideoComment.video_id, func.count(VideoComment.id))
        .where(VideoComment.video_id.in_(video_ids), VideoComment.deleted_at.is_(None))
        .group_by(VideoComment.video_id)
    )
    comments_count = {vid: cnt for vid, cnt in comments_rows.all()}

    reactions_rows = await db.execute(
        select(VideoReaction.video_id, func.count(VideoReaction.id))
        .where(VideoReaction.video_id.in_(video_ids))
        .group_by(VideoReaction.video_id)
    )
    reactions_count = {vid: cnt for vid, cnt in reactions_rows.all()}

    items: list[VideoOut] = []
    for video, author, author_profile in rows:
        cc = int(comments_count.get(video.id, 0))
        rc = int(reactions_count.get(video.id, 0))
        distance = None
        if (
            my_profile
            and my_profile.last_lat is not None
            and my_profile.last_lon is not None
            and author_profile
            and author_profile.last_lat is not None
            and author_profile.last_lon is not None
        ):
            distance = _distance_km(
                my_profile.last_lat,
                my_profile.last_lon,
                author_profile.last_lat,
                author_profile.last_lon,
            )
            if radius_km is not None and distance > radius_km:
                continue
        items.append(
            VideoOut(
                id=str(video.id),
                user_id=str(author.id),
                display_name=author.display_name,
                age=author.age,
                hide_age=bool(author.hide_age),
                gender=author.gender,
                asset_url=video.asset_url,
                caption=video.caption or "",
                comments_locked=video.comments_locked,
                comments_count=cc,
                reactions_count=rc,
                viewer_can_match_author=_viewer_can_match_author(my_user, my_profile, author, author_profile),
                viewer_follows_author=_viewer_follows_author(viewer_follows, author),
                distance_km=distance,
                session_expires_at=author_profile.session_expires_at.isoformat() if author_profile and author_profile.session_expires_at else None,
                created_at=video.created_at.isoformat(),
            )
        )
    if sort_by == "distance":
        items.sort(key=lambda item: (item.distance_km if item.distance_km is not None else 1e9, item.created_at), reverse=False)
    elif sort_by == "recent":
        items.sort(key=lambda item: item.created_at, reverse=True)
    else:
        items.sort(
            key=lambda item: (
                item.comments_count + item.reactions_count,
                -(item.distance_km or 9999),
                item.created_at,
            ),
            reverse=True,
        )
    return items


@router.get("/user/{target_user_id}", response_model=list[VideoOut])
async def videos_by_user(
    target_user_id: str,
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
):
    viewer_user = (await db.execute(select(User).where(User.id == user_id))).scalar_one_or_none()
    viewer_profile = (await db.execute(select(Profile).where(Profile.user_id == user_id))).scalar_one_or_none()
    query = (
        select(Video, User, Profile)
        .join(User, User.id == Video.user_id)
        .join(Profile, Profile.user_id == Video.user_id)
        .where(Video.user_id == target_user_id)
    )
    rows = (await db.execute(query)).all()
    video_ids = [video.id for video, _, _ in rows]
    if not video_ids:
        return []
    follows_rows = await db.execute(
        select(VideoFollow.target_user_id).where(VideoFollow.follower_id == user_id)
    )
    viewer_follows = {str(item) for item in follows_rows.scalars().all()}
    comments_rows = await db.execute(
        select(VideoComment.video_id, func.count(VideoComment.id))
        .where(VideoComment.video_id.in_(video_ids), VideoComment.deleted_at.is_(None))
        .group_by(VideoComment.video_id)
    )
    comments_count = {vid: cnt for vid, cnt in comments_rows.all()}
    reactions_rows = await db.execute(
        select(VideoReaction.video_id, func.count(VideoReaction.id))
        .where(VideoReaction.video_id.in_(video_ids))
        .group_by(VideoReaction.video_id)
    )
    reactions_count = {vid: cnt for vid, cnt in reactions_rows.all()}
    items: list[VideoOut] = []
    for video, author, author_profile in rows:
        items.append(
            VideoOut(
                id=str(video.id),
                user_id=str(author.id),
                display_name=author.display_name,
                age=author.age,
                hide_age=bool(author.hide_age),
                gender=author.gender,
                asset_url=video.asset_url,
                caption=video.caption or "",
                comments_locked=video.comments_locked,
                comments_count=int(comments_count.get(video.id, 0)),
                reactions_count=int(reactions_count.get(video.id, 0)),
                viewer_can_match_author=_viewer_can_match_author(viewer_user, viewer_profile, author, author_profile),
                viewer_follows_author=_viewer_follows_author(viewer_follows, author),
                session_expires_at=author_profile.session_expires_at.isoformat() if author_profile and author_profile.session_expires_at else None,
                created_at=video.created_at.isoformat(),
            )
        )
    items.sort(key=lambda item: item.created_at, reverse=True)
    return items


@router.get("/follow/{target_user_id}", response_model=FollowStatusOut)
async def follow_status(
    target_user_id: str,
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
):
    follow = (
        await db.execute(
            select(VideoFollow).where(
                VideoFollow.follower_id == user_id,
                VideoFollow.target_user_id == target_user_id,
            )
        )
    ).scalar_one_or_none()
    return FollowStatusOut(target_user_id=target_user_id, is_following=follow is not None)


@router.post("/follow/{target_user_id}", response_model=FollowStatusOut)
async def follow_user(
    target_user_id: str,
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
):
    if target_user_id == user_id:
        raise HTTPException(status_code=400, detail="cannot_follow_self")
    blocked = await db.execute(
        select(Block).where(
            or_(
                and_(Block.blocker_id == user_id, Block.blocked_user_id == target_user_id),
                and_(Block.blocker_id == target_user_id, Block.blocked_user_id == user_id),
            )
        )
    )
    if blocked.scalar_one_or_none():
        raise HTTPException(status_code=403, detail="blocked")
    existing = (
        await db.execute(
            select(VideoFollow).where(
                VideoFollow.follower_id == user_id,
                VideoFollow.target_user_id == target_user_id,
            )
        )
    ).scalar_one_or_none()
    if existing is None:
        db.add(VideoFollow(follower_id=user_id, target_user_id=target_user_id))
        await db.commit()
    return FollowStatusOut(target_user_id=target_user_id, is_following=True)


@router.delete("/follow/{target_user_id}", response_model=FollowStatusOut)
async def unfollow_user(
    target_user_id: str,
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
):
    follow = (
        await db.execute(
            select(VideoFollow).where(
                VideoFollow.follower_id == user_id,
                VideoFollow.target_user_id == target_user_id,
            )
        )
    ).scalar_one_or_none()
    if follow is not None:
        await db.delete(follow)
        await db.commit()
    return FollowStatusOut(target_user_id=target_user_id, is_following=False)


@router.get("/{video_id}/comments", response_model=list[VideoCommentOut])
async def get_comments(
    video_id: str,
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
):
    _ = user_id
    result_video = await db.execute(select(Video).where(Video.id == video_id))
    video = result_video.scalar_one_or_none()
    if not video:
        raise HTTPException(status_code=404, detail="video_not_found")

    rows = await db.execute(
        select(VideoComment, User)
        .join(User, User.id == VideoComment.user_id)
        .where(VideoComment.video_id == video.id)
        .order_by(VideoComment.created_at.asc())
    )
    result: list[VideoCommentOut] = []
    for comment, user in rows.all():
        result.append(
            VideoCommentOut(
                id=str(comment.id),
                video_id=str(comment.video_id),
                user_id=str(comment.user_id),
                display_name=user.display_name,
                parent_comment_id=str(comment.parent_comment_id) if comment.parent_comment_id else None,
                text=comment.text if comment.deleted_at is None else "",
                deleted=(comment.deleted_at is not None),
                created_at=comment.created_at.isoformat(),
            )
        )
    return result


@router.post("/{video_id}/comments", response_model=VideoCommentOut)
async def post_comment(
    video_id: str,
    payload: VideoCommentCreate,
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
):
    result_video = await db.execute(select(Video).where(Video.id == video_id))
    video = result_video.scalar_one_or_none()
    if not video:
        raise HTTPException(status_code=404, detail="video_not_found")

    author_profile = (await db.execute(select(Profile).where(Profile.user_id == video.user_id))).scalar_one_or_none()
    if video.comments_locked or not author_profile or not author_profile.is_online_toilet:
        raise HTTPException(status_code=403, detail="comments_locked")

    if payload.parent_comment_id:
        parent = (
            await db.execute(
                select(VideoComment).where(VideoComment.id == payload.parent_comment_id, VideoComment.video_id == video.id)
            )
        ).scalar_one_or_none()
        if not parent:
            raise HTTPException(status_code=404, detail="parent_comment_not_found")

    comment = VideoComment(
        video_id=video.id,
        user_id=user_id,
        parent_comment_id=payload.parent_comment_id,
        text=payload.text,
    )
    db.add(comment)
    await db.commit()
    await db.refresh(comment)

    author = (await db.execute(select(User).where(User.id == user_id))).scalar_one()
    return VideoCommentOut(
        id=str(comment.id),
        video_id=str(comment.video_id),
        user_id=str(comment.user_id),
        display_name=author.display_name,
        parent_comment_id=str(comment.parent_comment_id) if comment.parent_comment_id else None,
        text=comment.text,
        deleted=False,
        created_at=comment.created_at.isoformat(),
    )


@router.delete("/comments/{comment_id}")
async def delete_comment(
    comment_id: str,
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
):
    row = await db.execute(
        select(VideoComment, Video).join(Video, Video.id == VideoComment.video_id).where(VideoComment.id == comment_id)
    )
    pair = row.first()
    if not pair:
        raise HTTPException(status_code=404, detail="comment_not_found")
    comment, video = pair
    if str(comment.user_id) != user_id and str(video.user_id) != user_id:
        raise HTTPException(status_code=403, detail="forbidden")
    if comment.deleted_at is not None:
        return {"ok": True}
    comment.deleted_at = func.now()
    db.add(comment)
    await db.commit()
    return {"ok": True}


@router.post("/{video_id}/reactions")
async def react_video(
    video_id: str,
    payload: VideoReactionCreate,
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
):
    result_video = await db.execute(select(Video).where(Video.id == video_id))
    video = result_video.scalar_one_or_none()
    if not video:
        raise HTTPException(status_code=404, detail="video_not_found")

    author_profile = (await db.execute(select(Profile).where(Profile.user_id == video.user_id))).scalar_one_or_none()
    if video.comments_locked or not author_profile or not author_profile.is_online_toilet:
        raise HTTPException(status_code=403, detail="reactions_locked")

    reaction = VideoReaction(video_id=video.id, user_id=user_id, emoji=payload.emoji)
    db.add(reaction)
    await db.commit()
    return {"ok": True}


@router.delete("/{video_id}")
async def delete_video(
    video_id: str,
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
):
    result_video = await db.execute(select(Video).where(Video.id == video_id))
    video = result_video.scalar_one_or_none()
    if not video:
        raise HTTPException(status_code=404, detail="video_not_found")
    if str(video.user_id) != user_id:
        raise HTTPException(status_code=403, detail="forbidden")
    await db.delete(video)
    await db.commit()
    return {"ok": True}
