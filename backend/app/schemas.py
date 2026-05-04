from typing import List, Optional
from pydantic import conlist
from pydantic import BaseModel, Field
from .models import Tone, MatchStatus, ReportType, ReportStatus


class AuthRequest(BaseModel):
    id_token: str


class AuthResponse(BaseModel):
    access_token: str
    user_id: str


class ProfileSetup(BaseModel):
    age: int = Field(ge=18, le=99)
    gender: str = Field(default="unknown", pattern="^(male|female|other|unknown)$")
    hide_age: bool = False
    display_name: str = Field(min_length=2, max_length=32)
    bio_text: str = Field(default="", max_length=500)
    tone: Tone
    interests: List[str]
    looking_for_genders: conlist(str, max_length=3) = []
    toilet_selfie_url: str
    photos: conlist(str, max_length=10) = []
    consent_photo_ai: bool = False


class ProfileOut(BaseModel):
    user_id: str
    display_name: str
    age: int
    hide_age: bool = False
    gender: str
    bio_ai: str
    bio_text: str
    tone: Tone
    interests: List[str]
    looking_for_genders: List[str]
    toilet_selfie_url: str
    photos: List[str]
    session_video_url: Optional[str] = None
    session_expires_at: Optional[str] = None


class ProfileCardOut(BaseModel):
    user_id: str
    display_name: str
    age: int
    hide_age: bool = False
    gender: str
    bio_ai: str
    bio_text: str
    interests: List[str]
    looking_for_genders: List[str]
    toilet_selfie_url: str
    photos: List[str]
    session_video_url: Optional[str] = None
    is_online_toilet: bool
    distance_km: Optional[float] = None
    session_expires_at: Optional[str] = None


class LikeRequest(BaseModel):
    to_user_id: str
    action: str = Field(default="like", pattern="^(like|superlike|pass)$")
    message: Optional[str] = Field(default=None, max_length=240)


class MatchKeepRequest(BaseModel):
    match_id: str


class ReportRequest(BaseModel):
    target_user_id: str
    report_type: ReportType
    reason: Optional[str] = None
    object_id: Optional[str] = Field(default=None, max_length=128)


class BlockRequest(BaseModel):
    blocked_user_id: str


class BlockOut(BaseModel):
    blocker_id: str
    blocked_user_id: str


class MatchOut(BaseModel):
    id: str
    user_a_id: str
    user_b_id: str
    status: MatchStatus
    my_is_kept: bool = False
    other_is_kept: bool = False
    my_sessions_left: int = 0
    other_sessions_left: int = 0


class MatchListItemOut(BaseModel):
    id: str
    status: MatchStatus
    my_is_kept: bool = False
    other_is_kept: bool = False
    my_sessions_left: int = 0
    other_sessions_left: int = 0
    other_user_id: str
    display_name: str
    age: int
    hide_age: bool = False
    gender: str
    toilet_selfie_url: str
    is_online_toilet: bool
    session_expires_at: Optional[str] = None
    last_message: Optional[str] = None
    last_message_at: Optional[str] = None


class IncomingLikeOut(BaseModel):
    id: str
    from_user_id: str
    display_name: str
    age: int
    hide_age: bool = False
    gender: str
    toilet_selfie_url: str
    photos: List[str]
    bio_ai: str
    bio_text: str
    interests: List[str]
    session_video_url: Optional[str] = None
    is_online_toilet: bool
    session_expires_at: Optional[str] = None
    like_type: str
    message: Optional[str] = None
    created_at: str


class MessageCreate(BaseModel):
    text: str = Field(min_length=1, max_length=500)


class MessageOut(BaseModel):
    id: str
    match_id: str
    sender_id: str
    text: str
    created_at: str


class DeviceTokenRequest(BaseModel):
    token: str
    platform: str = "ios"


class PingRequest(BaseModel):
    target_user_id: str
    message: Optional[str] = None


class LocationUpdateRequest(BaseModel):
    lat: float
    lon: float


class SessionVideoRequest(BaseModel):
    asset_url: str
    caption: str = Field(default="", max_length=240)


class SessionStateRequest(BaseModel):
    active: bool


class VideoOut(BaseModel):
    id: str
    user_id: str
    display_name: str
    age: int
    hide_age: bool = False
    gender: str
    asset_url: str
    caption: str = ""
    comments_locked: bool
    comments_count: int
    reactions_count: int
    viewer_can_match_author: bool = False
    viewer_follows_author: bool = False
    distance_km: Optional[float] = None
    session_expires_at: Optional[str] = None
    created_at: str


class InboxSummaryOut(BaseModel):
    unread_activity_count: int
    unread_likes_count: int
    unread_matches_count: int


class InboxReadRequest(BaseModel):
    scope: str = Field(pattern="^(activity|likes|matches)$")


class FollowStatusOut(BaseModel):
    target_user_id: str
    is_following: bool


class VideoCommentCreate(BaseModel):
    text: str = Field(min_length=1, max_length=500)
    parent_comment_id: Optional[str] = None


class VideoCommentOut(BaseModel):
    id: str
    video_id: str
    user_id: str
    display_name: str
    parent_comment_id: Optional[str] = None
    text: str
    deleted: bool
    created_at: str


class VideoReactionCreate(BaseModel):
    emoji: str = Field(pattern="^(❤️|🚽|💩)$")


class ActivityItemOut(BaseModel):
    id: str
    event_type: str
    actor_user_id: str
    actor_display_name: str
    actor_age: int
    actor_gender: str
    actor_toilet_selfie_url: str
    actor_photos: List[str]
    actor_bio_ai: str
    actor_bio_text: str
    actor_interests: List[str]
    actor_session_video_url: Optional[str] = None
    actor_is_online_toilet: bool
    actor_session_expires_at: Optional[str] = None
    message: Optional[str] = None
    match_id: Optional[str] = None
    video_id: Optional[str] = None
    created_at: str


class ReportModerationOut(BaseModel):
    id: str
    reporter_user_id: str
    reporter_display_name: str
    target_user_id: str
    target_display_name: str
    report_type: ReportType
    object_id: Optional[str] = None
    reason: Optional[str] = None
    status: ReportStatus
    reviewed_at: Optional[str] = None
    reviewed_note: Optional[str] = None
    created_at: str


class ReportModerationUpdate(BaseModel):
    status: ReportStatus
    reviewed_note: Optional[str] = Field(default=None, max_length=500)


class ModerationSummaryOut(BaseModel):
    open_count: int
    reviewing_count: int
    resolved_count: int
    dismissed_count: int


class OpsSummaryOut(BaseModel):
    window_days: int
    total_users: int
    profiles_completed: int
    activated_users: int
    session_starts: int
    likes_sent: int
    superlikes_sent: int
    matches_created: int
    matches_with_messages: int
    kept_matches: int
    videos_published: int
    profile_completion_rate: float
    activation_rate: float
    like_to_match_rate: float
    match_to_first_message_rate: float
    message_to_kept_rate: float
    video_publish_rate: float
    moderation: ModerationSummaryOut
