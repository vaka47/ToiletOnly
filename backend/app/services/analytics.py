from __future__ import annotations

from datetime import datetime, timedelta, timezone
from typing import Any, Optional

from sqlalchemy import distinct, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from ..models import AnalyticsEvent, MatchStatus, Profile, Report, ReportStatus, User
from ..schemas import ModerationSummaryOut, OpsSummaryOut


async def track_event(
    db: AsyncSession,
    *,
    event_name: str,
    user_id: Optional[str] = None,
    target_user_id: Optional[str] = None,
    match_id: Optional[str] = None,
    source: str = "server",
    properties: Optional[dict[str, Any]] = None,
) -> AnalyticsEvent:
    event = AnalyticsEvent(
        user_id=user_id,
        target_user_id=target_user_id,
        match_id=match_id,
        event_name=event_name,
        source=source,
        properties=properties or {},
    )
    db.add(event)
    return event


async def build_ops_summary(db: AsyncSession, *, window_days: int = 30) -> OpsSummaryOut:
    now = datetime.now(timezone.utc)
    since = now - timedelta(days=window_days)

    total_users = int((await db.execute(select(func.count(User.id)))).scalar() or 0)
    profiles_completed = int((await db.execute(select(func.count(Profile.user_id)))).scalar() or 0)

    def _event_count_query(event_name: str):
        return select(func.count(AnalyticsEvent.id)).where(
            AnalyticsEvent.event_name == event_name,
            AnalyticsEvent.created_at >= since,
        )

    async def event_count(event_name: str) -> int:
        return int((await db.execute(_event_count_query(event_name))).scalar() or 0)

    async def distinct_user_count(event_name: str) -> int:
        return int(
            (
                await db.execute(
                    select(func.count(distinct(AnalyticsEvent.user_id))).where(
                        AnalyticsEvent.event_name == event_name,
                        AnalyticsEvent.created_at >= since,
                        AnalyticsEvent.user_id.is_not(None),
                    )
                )
            ).scalar()
            or 0
        )

    async def distinct_match_count(event_name: str) -> int:
        return int(
            (
                await db.execute(
                    select(func.count(distinct(AnalyticsEvent.match_id))).where(
                        AnalyticsEvent.event_name == event_name,
                        AnalyticsEvent.created_at >= since,
                        AnalyticsEvent.match_id.is_not(None),
                    )
                )
            ).scalar()
            or 0
        )

    activated_users = await distinct_user_count("session_started")
    session_starts = await event_count("session_started")
    likes_sent = await event_count("like_sent")
    superlikes_sent = await event_count("superlike_sent")
    matches_created = await event_count("match_created")
    matches_with_messages = await distinct_match_count("message_sent")
    kept_matches = await distinct_match_count("match_kept")
    videos_published = await event_count("video_published")
    video_publish_users = await distinct_user_count("video_published")

    moderation = ModerationSummaryOut(
        open_count=int((await db.execute(select(func.count(Report.id)).where(Report.status == ReportStatus.open))).scalar() or 0),
        reviewing_count=int((await db.execute(select(func.count(Report.id)).where(Report.status == ReportStatus.reviewing))).scalar() or 0),
        resolved_count=int((await db.execute(select(func.count(Report.id)).where(Report.status == ReportStatus.resolved))).scalar() or 0),
        dismissed_count=int((await db.execute(select(func.count(Report.id)).where(Report.status == ReportStatus.dismissed))).scalar() or 0),
    )

    total_like_actions = likes_sent + superlikes_sent

    def pct(numerator: int, denominator: int) -> float:
        if denominator <= 0:
            return 0.0
        return round((numerator / denominator) * 100.0, 2)

    return OpsSummaryOut(
        window_days=window_days,
        total_users=total_users,
        profiles_completed=profiles_completed,
        activated_users=activated_users,
        session_starts=session_starts,
        likes_sent=likes_sent,
        superlikes_sent=superlikes_sent,
        matches_created=matches_created,
        matches_with_messages=matches_with_messages,
        kept_matches=kept_matches,
        videos_published=videos_published,
        profile_completion_rate=pct(profiles_completed, total_users),
        activation_rate=pct(activated_users, profiles_completed),
        like_to_match_rate=pct(matches_created, total_like_actions),
        match_to_first_message_rate=pct(matches_with_messages, matches_created),
        message_to_kept_rate=pct(kept_matches, matches_with_messages),
        video_publish_rate=pct(video_publish_users, activated_users),
        moderation=moderation,
    )
