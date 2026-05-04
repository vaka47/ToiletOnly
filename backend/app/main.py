import os

from fastapi import FastAPI
from fastapi.staticfiles import StaticFiles
from starlette.middleware.gzip import GZipMiddleware
from sqlalchemy import text
from .db import engine, Base
from .config import settings
from .api import auth, profiles, likes, matches, media, reports, blocks, messages, devices, ping, videos, activity, ops
from .ws.chat import chat_socket
from .ws.presence import presence_socket

app = FastAPI(title="Toilet Dating API")
app.add_middleware(GZipMiddleware, minimum_size=1024)


@app.on_event("startup")
async def on_startup():
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
        # Lightweight schema upgrades for existing databases.
        await conn.execute(text("ALTER TABLE users ADD COLUMN IF NOT EXISTS gender VARCHAR NOT NULL DEFAULT 'unknown'"))
        await conn.execute(text("ALTER TABLE users ADD COLUMN IF NOT EXISTS hide_age BOOLEAN NOT NULL DEFAULT FALSE"))
        await conn.execute(text("ALTER TABLE users ADD COLUMN IF NOT EXISTS display_name_updated_at TIMESTAMPTZ NULL"))
        await conn.execute(
            text(
                "ALTER TABLE profiles ADD COLUMN IF NOT EXISTS superlike_used_in_session BOOLEAN NOT NULL DEFAULT FALSE"
            )
        )
        await conn.execute(
            text(
                "ALTER TABLE profiles ADD COLUMN IF NOT EXISTS looking_for_genders VARCHAR[] NOT NULL DEFAULT '{}'"
            )
        )
        await conn.execute(
            text(
                "ALTER TABLE profiles ADD COLUMN IF NOT EXISTS session_expires_at TIMESTAMPTZ NULL"
            )
        )
        await conn.execute(
            text(
                "ALTER TABLE profiles ADD COLUMN IF NOT EXISTS superlike_daily_count INTEGER NOT NULL DEFAULT 0"
            )
        )
        await conn.execute(
            text(
                "ALTER TABLE profiles ADD COLUMN IF NOT EXISTS superlike_daily_reset_at TIMESTAMPTZ NULL"
            )
        )
        await conn.execute(text("ALTER TABLE likes ADD COLUMN IF NOT EXISTS like_type VARCHAR NOT NULL DEFAULT 'like'"))
        await conn.execute(text("ALTER TABLE likes ADD COLUMN IF NOT EXISTS intro_message TEXT NULL"))
        await conn.execute(
            text(
                """
                CREATE TABLE IF NOT EXISTS passes (
                    id UUID PRIMARY KEY,
                    from_user_id UUID NOT NULL REFERENCES users(id),
                    to_user_id UUID NOT NULL REFERENCES users(id),
                    created_at TIMESTAMPTZ DEFAULT now()
                )
                """
            )
        )
        await conn.execute(
            text(
                """
                CREATE TABLE IF NOT EXISTS videos (
                    id UUID PRIMARY KEY,
                    user_id UUID NOT NULL REFERENCES users(id),
                    asset_url TEXT NOT NULL,
                    caption TEXT NOT NULL DEFAULT '',
                    comments_locked BOOLEAN NOT NULL DEFAULT FALSE,
                    created_at TIMESTAMPTZ DEFAULT now()
                )
                """
            )
        )
        await conn.execute(text("ALTER TABLE videos ADD COLUMN IF NOT EXISTS caption TEXT NOT NULL DEFAULT ''"))
        await conn.execute(
            text(
                """
                CREATE TABLE IF NOT EXISTS video_comments (
                    id UUID PRIMARY KEY,
                    video_id UUID NOT NULL REFERENCES videos(id),
                    user_id UUID NOT NULL REFERENCES users(id),
                    parent_comment_id UUID NULL REFERENCES video_comments(id),
                    text TEXT NOT NULL,
                    deleted_at TIMESTAMPTZ NULL,
                    created_at TIMESTAMPTZ DEFAULT now()
                )
                """
            )
        )
        await conn.execute(
            text(
                """
                CREATE TABLE IF NOT EXISTS video_reactions (
                    id UUID PRIMARY KEY,
                    video_id UUID NOT NULL REFERENCES videos(id),
                    user_id UUID NOT NULL REFERENCES users(id),
                    emoji VARCHAR NOT NULL,
                    created_at TIMESTAMPTZ DEFAULT now()
                )
                """
            )
        )
        await conn.execute(
            text(
                """
                CREATE TABLE IF NOT EXISTS video_follows (
                    follower_id UUID NOT NULL REFERENCES users(id),
                    target_user_id UUID NOT NULL REFERENCES users(id),
                    created_at TIMESTAMPTZ DEFAULT now(),
                    PRIMARY KEY (follower_id, target_user_id)
                )
                """
            )
        )
        await conn.execute(
            text(
                """
                CREATE TABLE IF NOT EXISTS inbox_states (
                    user_id UUID PRIMARY KEY REFERENCES users(id),
                    activity_seen_at TIMESTAMPTZ NULL,
                    likes_seen_at TIMESTAMPTZ NULL,
                    matches_seen_at TIMESTAMPTZ NULL,
                    created_at TIMESTAMPTZ DEFAULT now(),
                    updated_at TIMESTAMPTZ DEFAULT now()
                )
                """
            )
        )
        await conn.execute(
            text(
                """
                CREATE TABLE IF NOT EXISTS match_participant_states (
                    match_id UUID NOT NULL REFERENCES matches(id),
                    user_id UUID NOT NULL REFERENCES users(id),
                    sessions_left INTEGER NOT NULL DEFAULT 2,
                    is_kept BOOLEAN NOT NULL DEFAULT FALSE,
                    updated_at TIMESTAMPTZ DEFAULT now(),
                    PRIMARY KEY (match_id, user_id)
                )
                """
            )
        )
        await conn.execute(text("ALTER TABLE reports ADD COLUMN IF NOT EXISTS object_id VARCHAR NULL"))
        await conn.execute(text("ALTER TABLE reports ADD COLUMN IF NOT EXISTS status VARCHAR NOT NULL DEFAULT 'open'"))
        await conn.execute(text("ALTER TABLE reports ADD COLUMN IF NOT EXISTS reviewed_at TIMESTAMPTZ NULL"))
        await conn.execute(text("ALTER TABLE reports ADD COLUMN IF NOT EXISTS reviewed_note TEXT NULL"))
        await conn.execute(text("ALTER TABLE reports ADD COLUMN IF NOT EXISTS reviewer_user_id UUID NULL REFERENCES users(id)"))
        await conn.execute(
            text(
                """
                CREATE TABLE IF NOT EXISTS analytics_events (
                    id UUID PRIMARY KEY,
                    user_id UUID NULL REFERENCES users(id),
                    target_user_id UUID NULL REFERENCES users(id),
                    match_id UUID NULL REFERENCES matches(id),
                    event_name VARCHAR NOT NULL,
                    source VARCHAR NOT NULL DEFAULT 'server',
                    properties JSON NOT NULL DEFAULT '{}'::json,
                    created_at TIMESTAMPTZ DEFAULT now()
                )
                """
            )
        )
        await conn.execute(
            text("CREATE INDEX IF NOT EXISTS ix_profiles_online_session ON profiles (is_online_toilet, session_expires_at)")
        )
        await conn.execute(
            text("CREATE INDEX IF NOT EXISTS ix_videos_user_created ON videos (user_id, created_at DESC)")
        )
        await conn.execute(
            text("CREATE INDEX IF NOT EXISTS ix_video_comments_video_created ON video_comments (video_id, created_at ASC)")
        )
        await conn.execute(
            text("CREATE INDEX IF NOT EXISTS ix_video_reactions_video_created ON video_reactions (video_id, created_at DESC)")
        )
        await conn.execute(
            text("CREATE INDEX IF NOT EXISTS ix_reports_status_created ON reports (status, created_at DESC)")
        )
        await conn.execute(
            text("CREATE INDEX IF NOT EXISTS ix_analytics_events_name_created ON analytics_events (event_name, created_at DESC)")
        )
        await conn.execute(
            text("CREATE INDEX IF NOT EXISTS ix_likes_to_user_created ON likes (to_user_id, created_at DESC)")
        )
        await conn.execute(
            text("CREATE INDEX IF NOT EXISTS ix_messages_match_created ON messages (match_id, created_at ASC)")
        )


app.include_router(auth.router)
app.include_router(profiles.router)
app.include_router(likes.router)
app.include_router(matches.router)
app.include_router(messages.router)
app.include_router(media.router)
app.include_router(reports.router)
app.include_router(blocks.router)
app.include_router(devices.router)
app.include_router(ping.router)
app.include_router(videos.router)
app.include_router(activity.router)
app.include_router(ops.router)

os.makedirs(settings.media_storage_path, exist_ok=True)
app.mount("/media", StaticFiles(directory=settings.media_storage_path), name="media")


@app.get("/health/live")
async def health_live():
    return {"ok": True, "environment": settings.environment}


@app.get("/health/ready")
async def health_ready():
    async with engine.connect() as conn:
        await conn.execute(text("SELECT 1"))
    media_ok = os.path.isdir(settings.media_storage_path)
    return {"ok": media_ok, "database": True, "media_storage": media_ok}


@app.websocket("/ws/chat/{match_id}")
async def ws_chat(ws, match_id: str):
    await chat_socket(ws, match_id)


@app.websocket("/ws/presence")
async def ws_presence(ws):
    await presence_socket(ws)
