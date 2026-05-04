import enum
import uuid
from sqlalchemy import Column, String, Integer, DateTime, Boolean, ForeignKey, Text, Enum, ARRAY, Float, JSON
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.sql import func
from .db import Base


class Tone(str, enum.Enum):
    meme = "meme"
    flirty = "flirty"
    chill = "chill"
    nerdy = "nerdy"


class MatchStatus(str, enum.Enum):
    pending = "pending"
    active = "active"
    expired = "expired"
    kept = "kept"


class ReportType(str, enum.Enum):
    photo = "photo"
    video = "video"
    chat = "chat"
    profile = "profile"


class ReportStatus(str, enum.Enum):
    open = "open"
    reviewing = "reviewing"
    resolved = "resolved"
    dismissed = "dismissed"


class User(Base):
    __tablename__ = "users"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    apple_sub = Column(String, unique=True, nullable=False)
    display_name = Column(String, nullable=False, default="ToiletUser")
    display_name_updated_at = Column(DateTime(timezone=True), nullable=True)
    age = Column(Integer, nullable=False)
    gender = Column(String, nullable=False, default="unknown")
    hide_age = Column(Boolean, nullable=False, default=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())


class Profile(Base):
    __tablename__ = "profiles"

    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), primary_key=True)
    bio_ai = Column(Text, nullable=False, default="")
    bio_text = Column(Text, nullable=False, default="")
    tone = Column(Enum(Tone), nullable=False, default=Tone.meme)
    interests = Column(ARRAY(String), nullable=False, default=[])
    looking_for_genders = Column(ARRAY(String), nullable=False, default=[])
    toilet_selfie_url = Column(Text, nullable=False)
    photos = Column(ARRAY(String), nullable=False, default=[])
    session_video_url = Column(Text, nullable=True)
    consent_photo_ai = Column(Boolean, default=False)
    is_online_toilet = Column(Boolean, default=False)
    session_expires_at = Column(DateTime(timezone=True), nullable=True)
    superlike_used_in_session = Column(Boolean, nullable=False, default=False)
    superlike_daily_count = Column(Integer, nullable=False, default=0)
    superlike_daily_reset_at = Column(DateTime(timezone=True), nullable=True)
    last_lat = Column(Float, nullable=True)
    last_lon = Column(Float, nullable=True)
    last_active_at = Column(DateTime(timezone=True), server_default=func.now())


class Like(Base):
    __tablename__ = "likes"

    from_user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), primary_key=True)
    to_user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), primary_key=True)
    like_type = Column(String, nullable=False, default="like")
    intro_message = Column(Text, nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())


class Pass(Base):
    __tablename__ = "passes"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    from_user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    to_user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())


class Match(Base):
    __tablename__ = "matches"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_a_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    user_b_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    status = Column(Enum(MatchStatus), nullable=False, default=MatchStatus.pending)
    expires_at = Column(DateTime(timezone=True), nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())


class MatchParticipantState(Base):
    __tablename__ = "match_participant_states"

    match_id = Column(UUID(as_uuid=True), ForeignKey("matches.id"), primary_key=True)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), primary_key=True)
    sessions_left = Column(Integer, nullable=False, default=2)
    is_kept = Column(Boolean, nullable=False, default=False)
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())


class Message(Base):
    __tablename__ = "messages"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    match_id = Column(UUID(as_uuid=True), ForeignKey("matches.id"), nullable=False)
    sender_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    text = Column(Text, nullable=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())


class Video(Base):
    __tablename__ = "videos"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    asset_url = Column(Text, nullable=False)
    caption = Column(Text, nullable=False, default="")
    comments_locked = Column(Boolean, nullable=False, default=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())


class VideoFollow(Base):
    __tablename__ = "video_follows"

    follower_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), primary_key=True)
    target_user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), primary_key=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())


class VideoComment(Base):
    __tablename__ = "video_comments"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    video_id = Column(UUID(as_uuid=True), ForeignKey("videos.id"), nullable=False)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    parent_comment_id = Column(UUID(as_uuid=True), ForeignKey("video_comments.id"), nullable=True)
    text = Column(Text, nullable=False)
    deleted_at = Column(DateTime(timezone=True), nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())


class VideoReaction(Base):
    __tablename__ = "video_reactions"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    video_id = Column(UUID(as_uuid=True), ForeignKey("videos.id"), nullable=False)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    emoji = Column(String, nullable=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())


class Report(Base):
    __tablename__ = "reports"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    reporter_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    target_user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    report_type = Column(Enum(ReportType), nullable=False)
    object_id = Column(String, nullable=True)
    reason = Column(Text, nullable=True)
    status = Column(Enum(ReportStatus), nullable=False, default=ReportStatus.open)
    reviewed_at = Column(DateTime(timezone=True), nullable=True)
    reviewed_note = Column(Text, nullable=True)
    reviewer_user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())


class Block(Base):
    __tablename__ = "blocks"

    blocker_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), primary_key=True)
    blocked_user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), primary_key=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())


class DeviceToken(Base):
    __tablename__ = "device_tokens"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    token = Column(String, nullable=False, unique=True)
    platform = Column(String, nullable=False, default="ios")
    created_at = Column(DateTime(timezone=True), server_default=func.now())


class InboxState(Base):
    __tablename__ = "inbox_states"

    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), primary_key=True)
    activity_seen_at = Column(DateTime(timezone=True), nullable=True)
    likes_seen_at = Column(DateTime(timezone=True), nullable=True)
    matches_seen_at = Column(DateTime(timezone=True), nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())


class Ping(Base):
    __tablename__ = "pings"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    sender_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    target_user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    message = Column(Text, nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())


class AnalyticsEvent(Base):
    __tablename__ = "analytics_events"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=True)
    target_user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=True)
    match_id = Column(UUID(as_uuid=True), ForeignKey("matches.id"), nullable=True)
    event_name = Column(String, nullable=False)
    source = Column(String, nullable=False, default="server")
    properties = Column(JSON, nullable=False, default=dict)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
