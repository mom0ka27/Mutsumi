from datetime import datetime
from typing import Any

from pydantic import BaseModel, ConfigDict, Field


DEFAULT_RESOLUTION = ["1080p", "2160p"]
DEFAULT_CODEC = ["av1", "hevc", "avc"]
DEFAULT_SUBTITLE = ["日", "无"]
DEFAULT_BITDEPTH = ["10bit", "8bit"]
DEFAULT_WEIGHTS = {
    "fansub": 45,
    "resolution": 22,
    "codec": 15,
    "subtitle": 12,
    "bitdepth": 6,
}


class PreferenceProfileCreate(BaseModel):
    name: str = Field(default="默认", min_length=1, max_length=128)
    is_default: bool = False
    language_mode: str = "简"
    language_unknown: str = "accept"
    must_include: list[str] = Field(default_factory=list)
    exclude_tokens: list[str] = Field(default_factory=list)
    prefer_resolution: list[str] = Field(default_factory=lambda: list(DEFAULT_RESOLUTION))
    prefer_codec: list[str] = Field(default_factory=lambda: list(DEFAULT_CODEC))
    prefer_subtitle: list[str] = Field(default_factory=lambda: list(DEFAULT_SUBTITLE))
    prefer_bitdepth: list[str] = Field(default_factory=lambda: list(DEFAULT_BITDEPTH))
    weights: dict[str, float] = Field(default_factory=lambda: dict(DEFAULT_WEIGHTS))
    neutral_score: float = Field(default=0.5, ge=0, le=1)
    accept_now_score: float = Field(default=0.85, ge=0, le=1)
    grace_hours: float = Field(default=3.0, ge=0)


class PreferenceProfileUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=128)
    is_default: bool | None = None
    language_mode: str | None = None
    language_unknown: str | None = None
    must_include: list[str] | None = None
    exclude_tokens: list[str] | None = None
    prefer_resolution: list[str] | None = None
    prefer_codec: list[str] | None = None
    prefer_subtitle: list[str] | None = None
    prefer_bitdepth: list[str] | None = None
    weights: dict[str, float] | None = None
    neutral_score: float | None = Field(default=None, ge=0, le=1)
    accept_now_score: float | None = Field(default=None, ge=0, le=1)
    grace_hours: float | None = Field(default=None, ge=0)


class PreferenceProfileRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    name: str
    is_default: bool
    language_mode: str
    language_unknown: str
    must_include: list[str]
    exclude_tokens: list[str]
    prefer_resolution: list[str]
    prefer_codec: list[str]
    prefer_subtitle: list[str]
    prefer_bitdepth: list[str]
    weights: dict[str, float]
    neutral_score: float
    accept_now_score: float
    grace_hours: float


class SubscriptionCreate(BaseModel):
    anime_id: int = Field(gt=0)
    profile_id: int | None = Field(default=None, gt=0)
    enabled: bool = True
    fansubs: list[str] = Field(default_factory=list)
    allow_no_fansub: bool = False
    search_keywords: list[str] = Field(default_factory=list)
    must_include: list[str] = Field(default_factory=list)
    exclude_keywords: list[str] = Field(default_factory=list)
    use_subject_id: bool = True
    resource_types: list[str] = Field(default_factory=lambda: ["动画"])
    profile_overrides: dict[str, Any] | None = None
    episode_offset_override: int | None = None


class SubscriptionUpdate(BaseModel):
    profile_id: int | None = Field(default=None, gt=0)
    enabled: bool | None = None
    fansubs: list[str] | None = None
    allow_no_fansub: bool | None = None
    search_keywords: list[str] | None = None
    must_include: list[str] | None = None
    exclude_keywords: list[str] | None = None
    use_subject_id: bool | None = None
    resource_types: list[str] | None = None
    profile_overrides: dict[str, Any] | None = None
    episode_offset_override: int | None = None


class SubscriptionRead(BaseModel):
    id: int
    anime_id: int
    anime_name: str
    anime_name_cn: str
    image_url: str
    enabled: bool
    profile_id: int
    fansubs: list[str]
    allow_no_fansub: bool
    search_keywords: list[str]
    must_include: list[str]
    exclude_keywords: list[str]
    use_subject_id: bool
    resource_types: list[str]
    profile_overrides: dict[str, Any] | None
    episode_offset_override: int | None
    cursor_at: datetime | None
    last_checked_at: datetime | None
    last_found_at: datetime | None
    last_error: str | None
    created_by: int
    next_check_at: datetime | None = None


class SubscriptionEpisodeRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    subscription_id: int
    episode_index: int | None
    resource_id: int
    resource_title: str
    score: float
    attributes: dict[str, Any]
    download_hash: str | None
    state: str
    reason: str | None
    first_seen_at: datetime
    created_at: datetime
    updated_at: datetime


class FansubCandidateRead(BaseModel):
    name: str
    count: int
    latest_at: datetime | None = None
    is_no_fansub: bool = False


class SubscriptionPreviewRequest(SubscriptionCreate):
    pass


class SubscriptionPreviewCandidateRead(BaseModel):
    episode_index: int | None
    resource_id: int
    resource_title: str
    fansub: str
    score: float
    state: str
    reason: str | None
    attributes: dict[str, Any]
    selected: bool = False
    created_at: datetime | None = None


class SubscriptionPreviewRead(BaseModel):
    anime_id: int
    resource_count: int
    accepted_count: int
    candidates: list[SubscriptionPreviewCandidateRead]


class SubscriptionCheckRead(BaseModel):
    subscription: SubscriptionRead
    processed: int
    found: int
