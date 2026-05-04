from __future__ import annotations

import random
from datetime import datetime, timedelta, timezone
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, and_, or_
from ..db import get_db
from ..models import (
    Profile,
    Block,
    User,
    Video,
    VideoFollow,
    VideoComment,
    VideoReaction,
    Like,
    Pass,
    Match,
    Message,
    DeviceToken,
    Ping,
    MatchParticipantState,
)
from ..schemas import (
    ProfileSetup,
    ProfileOut,
    ProfileCardOut,
    LocationUpdateRequest,
    SessionVideoRequest,
    SessionStateRequest,
)
from ..security import get_current_user_id
from ..services.analytics import track_event
from ..services.apns import send_push
from ..services.match_policy import consume_sessions_on_start
from math import radians, sin, cos, sqrt, atan2

router = APIRouter(prefix="/profiles", tags=["profiles"])

ALLOWED_GENDERS = {"male", "female", "other", "unknown"}
DISPLAY_NAME_COOLDOWN_DAYS = 30


@router.post("/setup", response_model=ProfileOut)
async def setup_profile(
    payload: ProfileSetup,
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
):
    if len(payload.photos) > 10:
        raise HTTPException(status_code=400, detail="too many photos")
    invalid_preferences = [item for item in payload.looking_for_genders if item not in {"male", "female", "other"}]
    if invalid_preferences:
        raise HTTPException(status_code=400, detail="invalid_looking_for_genders")
    result = await db.execute(select(User).where(User.id == user_id))
    user = result.scalar_one()
    now = datetime.now(timezone.utc)
    requested_display_name = payload.display_name.strip() or "ToiletUser"
    if requested_display_name != user.display_name:
        if user.display_name_updated_at and now - user.display_name_updated_at < timedelta(days=DISPLAY_NAME_COOLDOWN_DAYS):
            raise HTTPException(status_code=400, detail="display_name_cooldown")
        user.display_name = requested_display_name
        user.display_name_updated_at = now
    elif user.display_name_updated_at is None:
        user.display_name_updated_at = now
    user.age = payload.age
    user.gender = payload.gender
    user.hide_age = payload.hide_age

    result_profile = await db.execute(select(Profile).where(Profile.user_id == user_id))
    profile = result_profile.scalar_one_or_none()
    if profile is None:
        profile = Profile(
            user_id=user_id,
            bio_ai="",
            bio_text=payload.bio_text,
            tone=payload.tone,
            interests=payload.interests,
            looking_for_genders=payload.looking_for_genders,
            toilet_selfie_url=payload.toilet_selfie_url,
            photos=payload.photos,
            consent_photo_ai=payload.consent_photo_ai,
        )
        db.add(profile)
    else:
        profile.bio_text = payload.bio_text
        profile.tone = payload.tone
        profile.interests = payload.interests
        profile.looking_for_genders = payload.looking_for_genders
        profile.photos = payload.photos
        profile.consent_photo_ai = payload.consent_photo_ai
        if payload.toilet_selfie_url:
            profile.toilet_selfie_url = payload.toilet_selfie_url
    await track_event(
        db,
        event_name="profile_setup_completed",
        user_id=str(user.id),
        source="server",
        properties={
            "photo_count": len(payload.photos),
            "interest_count": len(payload.interests),
            "looking_for_count": len(payload.looking_for_genders),
            "hide_age": payload.hide_age,
        },
    )
    await db.commit()
    return ProfileOut(
        user_id=user_id,
        display_name=user.display_name,
        age=user.age,
        hide_age=user.hide_age,
        gender=user.gender,
        bio_ai="",
        bio_text=profile.bio_text,
        tone=payload.tone,
        interests=payload.interests,
        looking_for_genders=profile.looking_for_genders,
        toilet_selfie_url=profile.toilet_selfie_url,
        photos=payload.photos,
        session_video_url=None,
        session_expires_at=profile.session_expires_at.isoformat() if profile.session_expires_at else None,
    )


@router.get("/user/{profile_id}", response_model=ProfileOut)
async def get_profile(
    profile_id: str,
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
):
    block_check = await db.execute(
        select(Block).where(
            or_(
                and_(Block.blocker_id == user_id, Block.blocked_user_id == profile_id),
                and_(Block.blocker_id == profile_id, Block.blocked_user_id == user_id),
            )
        )
    )
    if block_check.scalar_one_or_none():
        raise HTTPException(status_code=403, detail="blocked")

    result = await db.execute(select(Profile).where(Profile.user_id == profile_id))
    profile = result.scalar_one()
    user_result = await db.execute(select(User).where(User.id == profile.user_id))
    user = user_result.scalar_one()
    return ProfileOut(
        user_id=str(profile.user_id),
        display_name=user.display_name,
        age=user.age,
        hide_age=user.hide_age,
        gender=user.gender,
        bio_ai=profile.bio_ai,
        bio_text=profile.bio_text,
        tone=profile.tone,
        interests=profile.interests,
        looking_for_genders=profile.looking_for_genders,
        toilet_selfie_url=profile.toilet_selfie_url,
        photos=profile.photos,
        session_video_url=profile.session_video_url,
        session_expires_at=profile.session_expires_at.isoformat() if profile.session_expires_at else None,
    )

@router.post("/location")
async def update_location(
    payload: LocationUpdateRequest,
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
):
    result = await db.execute(select(Profile).where(Profile.user_id == user_id))
    profile = result.scalar_one_or_none()
    if profile is None:
        raise HTTPException(status_code=404, detail="profile not found")
    profile.last_lat = payload.lat
    profile.last_lon = payload.lon
    await db.commit()
    return {"ok": True}


@router.post("/session-video")
async def update_session_video(
    payload: SessionVideoRequest,
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
):
    now = datetime.now(timezone.utc)
    result = await db.execute(select(Profile).where(Profile.user_id == user_id))
    profile = result.scalar_one_or_none()
    if profile is None:
        raise HTTPException(status_code=404, detail="profile not found")
    if not profile.is_online_toilet or not profile.session_expires_at or profile.session_expires_at <= now:
        raise HTTPException(status_code=400, detail="inactive_session")
    profile.session_video_url = payload.asset_url
    video = Video(
        user_id=profile.user_id,
        asset_url=payload.asset_url,
        caption=payload.caption.strip(),
        comments_locked=False,
    )
    db.add(video)
    author = (await db.execute(select(User).where(User.id == user_id))).scalar_one()
    await db.flush()
    await track_event(
        db,
        event_name="video_published",
        user_id=user_id,
        source="server",
        properties={"caption_length": len(payload.caption.strip()), "video_id": str(video.id)},
    )
    await db.commit()
    follower_rows = (
        await db.execute(
            select(DeviceToken)
            .join(VideoFollow, VideoFollow.follower_id == DeviceToken.user_id)
            .where(VideoFollow.target_user_id == user_id)
        )
    ).scalars().all()
    for token in follower_rows:
        await send_push(
            device_token=token.token,
            title=f"{author.display_name} сейчас в туалете",
            body=payload.caption.strip() or "У этого профиля появилось новое видео в текущей сессии.",
            data={"type": "followed_user_live", "user_id": str(user_id), "video_id": str(video.id)},
        )
    return {"ok": True, "video_id": str(video.id)}


@router.post("/session-state")
async def update_session_state(
    payload: SessionStateRequest,
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
):
    result = await db.execute(select(Profile).where(Profile.user_id == user_id))
    profile = result.scalar_one_or_none()
    if profile is None:
        raise HTTPException(status_code=404, detail="profile not found")

    was_online = bool(profile.is_online_toilet)
    profile.is_online_toilet = payload.active
    profile.last_active_at = datetime.now(timezone.utc)
    db.add(profile)

    consumed = 0
    if payload.active:
        if not was_online:
            profile.superlike_used_in_session = False
        profile.session_expires_at = datetime.now(timezone.utc) + timedelta(minutes=15)
        consumed = await consume_sessions_on_start(db, profile.user_id)
        if not was_online:
            await track_event(
                db,
                event_name="session_started",
                user_id=user_id,
                source="server",
                properties={"consumed_matches": consumed},
            )
    else:
        profile.session_expires_at = None
        videos = await db.execute(
            select(Video).where(Video.user_id == profile.user_id, Video.comments_locked.is_(False))
        )
        for item in videos.scalars().all():
            item.comments_locked = True
            db.add(item)
        if was_online:
            await track_event(
                db,
                event_name="session_ended",
                user_id=user_id,
                source="server",
                properties={},
            )

    await db.commit()
    return {"ok": True, "consumed_matches": consumed}


def _distance_km(a_lat: float, a_lon: float, b_lat: float, b_lon: float) -> float:
    r = 6371.0
    dlat = radians(b_lat - a_lat)
    dlon = radians(b_lon - a_lon)
    lat1 = radians(a_lat)
    lat2 = radians(b_lat)
    h = sin(dlat / 2) ** 2 + cos(lat1) * cos(lat2) * sin(dlon / 2) ** 2
    return 2 * r * atan2(sqrt(h), sqrt(1 - h))


@router.get("/feed", response_model=list[ProfileCardOut])
async def get_feed(
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
    age_min: Optional[int] = Query(default=None, ge=18, le=100),
    age_max: Optional[int] = Query(default=None, ge=18, le=100),
    show_nearby: bool = Query(default=False),
    target_gender: Optional[str] = Query(default=None),
    radius_km: Optional[float] = Query(default=None, ge=1, le=500),
):
    now = datetime.now(timezone.utc)
    result_me = await db.execute(select(Profile).where(Profile.user_id == user_id))
    my_profile = result_me.scalar_one_or_none()
    my_user = (await db.execute(select(User).where(User.id == user_id))).scalar_one_or_none()

    blocked_exists = (
        select(Block)
        .where(
            or_(
                and_(Block.blocker_id == user_id, Block.blocked_user_id == Profile.user_id),
                and_(Block.blocker_id == Profile.user_id, Block.blocked_user_id == user_id),
            )
        )
        .exists()
    )

    query = (
        select(Profile, User)
        .join(User, User.id == Profile.user_id)
        .where(Profile.user_id != user_id)
        .where(~blocked_exists)
    )
    if age_min is not None:
        query = query.where(User.age >= age_min)
    if age_max is not None:
        query = query.where(User.age <= age_max)

    preferred_genders: list[str] = []
    if target_gender and target_gender in {"male", "female", "other"}:
        preferred_genders = [target_gender]
    elif my_profile and my_profile.looking_for_genders:
        preferred_genders = [item for item in my_profile.looking_for_genders if item in {"male", "female", "other"}]
    if preferred_genders:
        query = query.where(User.gender.in_(preferred_genders))

    result = await db.execute(query)
    rows = result.all()
    ranked_items: list[tuple[float, ProfileCardOut]] = []
    for profile, user in rows:
        if user.gender not in ALLOWED_GENDERS:
            continue
        if my_user and profile.looking_for_genders and my_user.gender not in profile.looking_for_genders:
            continue
        distance = None
        if show_nearby and my_profile and my_profile.last_lat is not None and my_profile.last_lon is not None:
            if profile.last_lat is not None and profile.last_lon is not None:
                distance = _distance_km(
                    my_profile.last_lat,
                    my_profile.last_lon,
                    profile.last_lat,
                    profile.last_lon,
                )
                if distance > (radius_km if radius_km is not None else 50):
                    continue
        is_online = bool(profile.is_online_toilet and profile.session_expires_at and profile.session_expires_at > now)
        item = ProfileCardOut(
            user_id=str(profile.user_id),
            display_name=user.display_name,
            age=user.age,
            hide_age=user.hide_age,
            gender=user.gender,
            bio_ai=profile.bio_ai,
            bio_text=profile.bio_text,
            interests=profile.interests,
            looking_for_genders=profile.looking_for_genders,
            toilet_selfie_url=profile.toilet_selfie_url,
            photos=profile.photos,
            session_video_url=profile.session_video_url,
            is_online_toilet=is_online,
            distance_km=distance,
            session_expires_at=profile.session_expires_at.isoformat() if profile.session_expires_at else None,
        )
        online_bonus = 120 if is_online else 0
        nearby_bonus = 0
        if distance is not None:
            nearby_bonus = max(0, 40 - min(distance, 40))
        freshness_bonus = 0
        if profile.last_active_at:
            freshness_bonus = max(0.0, 10 - min((now - profile.last_active_at).total_seconds() / 60.0, 10))
        randomness = random.random() * 15
        ranked_items.append((online_bonus + nearby_bonus + freshness_bonus + randomness, item))

    ranked_items.sort(key=lambda pair: pair[0], reverse=True)
    items = [item for _, item in ranked_items]
    if show_nearby:
        items.sort(
            key=lambda item: (
                0 if item.is_online_toilet else 1,
                item.distance_km if item.distance_km is not None else 1e9,
                -random.random(),
            )
        )
    return items


@router.delete("/me")
async def delete_my_profile(
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
):
    uid = user_id
    for model, col in [
        (DeviceToken, DeviceToken.user_id),
        (Ping, Ping.sender_id),
        (Ping, Ping.target_user_id),
        (Like, Like.from_user_id),
        (Like, Like.to_user_id),
        (Pass, Pass.from_user_id),
        (Pass, Pass.to_user_id),
        (Block, Block.blocker_id),
        (Block, Block.blocked_user_id),
        (VideoReaction, VideoReaction.user_id),
        (VideoComment, VideoComment.user_id),
    ]:
        rows = await db.execute(select(model).where(col == uid))
        for item in rows.scalars().all():
            await db.delete(item)

    user_videos = (await db.execute(select(Video).where(Video.user_id == uid))).scalars().all()
    for video in user_videos:
        comments = (await db.execute(select(VideoComment).where(VideoComment.video_id == video.id))).scalars().all()
        for comment in comments:
            await db.delete(comment)
        reactions = (await db.execute(select(VideoReaction).where(VideoReaction.video_id == video.id))).scalars().all()
        for reaction in reactions:
            await db.delete(reaction)
        await db.delete(video)

    matches = (
        await db.execute(
            select(Match).where(or_(Match.user_a_id == uid, Match.user_b_id == uid))
        )
    ).scalars().all()
    for match in matches:
        states = (await db.execute(select(MatchParticipantState).where(MatchParticipantState.match_id == match.id))).scalars().all()
        for state in states:
            await db.delete(state)
        messages = (await db.execute(select(Message).where(Message.match_id == match.id))).scalars().all()
        for message in messages:
            await db.delete(message)
        await db.delete(match)

    profile_result = await db.execute(select(Profile).where(Profile.user_id == user_id))
    profile = profile_result.scalar_one_or_none()
    if profile is not None:
        await db.delete(profile)
    user_result = await db.execute(select(User).where(User.id == user_id))
    user = user_result.scalar_one_or_none()
    if user is not None:
        await db.delete(user)
    await db.commit()
    return {"ok": True}
