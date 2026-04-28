import os

from fastapi import FastAPI
from fastapi.staticfiles import StaticFiles
from sqlalchemy import text
from .db import engine, Base
from .config import settings
from .api import auth, profiles, likes, matches, media, reports, blocks, messages, devices, ping, videos, activity
from .ws.chat import chat_socket
from .ws.presence import presence_socket

app = FastAPI(title="Toilet Dating API")


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

os.makedirs(settings.media_storage_path, exist_ok=True)
app.mount("/media", StaticFiles(directory=settings.media_storage_path), name="media")


@app.websocket("/ws/chat/{match_id}")
async def ws_chat(ws, match_id: str):
    await chat_socket(ws, match_id)


@app.websocket("/ws/presence")
async def ws_presence(ws):
    await presence_socket(ws)
