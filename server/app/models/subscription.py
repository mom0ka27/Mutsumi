from datetime import UTC, datetime

from sqlalchemy import DateTime, Float, ForeignKey, Index, Integer, JSON, String, Text
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.session import Base


def utcnow() -> datetime:
    """Return a naive UTC value that works consistently with SQLite."""
    return datetime.now(UTC).replace(tzinfo=None)


class PreferenceProfile(Base):
    __tablename__ = "preference_profiles"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    name: Mapped[str] = mapped_column(String(128))
    is_default: Mapped[bool] = mapped_column(default=False)

    language_mode: Mapped[str] = mapped_column(String(16), default="简")
    language_unknown: Mapped[str] = mapped_column(String(16), default="accept")
    must_include: Mapped[list[str]] = mapped_column(JSON, default=list)
    exclude_tokens: Mapped[list[str]] = mapped_column(JSON, default=list)

    prefer_resolution: Mapped[list[str]] = mapped_column(JSON, default=list)
    prefer_codec: Mapped[list[str]] = mapped_column(JSON, default=list)
    prefer_subtitle: Mapped[list[str]] = mapped_column(JSON, default=list)
    prefer_bitdepth: Mapped[list[str]] = mapped_column(JSON, default=list)
    weights: Mapped[dict[str, float]] = mapped_column(JSON, default=dict)
    neutral_score: Mapped[float] = mapped_column(Float, default=0.5)
    accept_now_score: Mapped[float] = mapped_column(Float, default=0.85)
    grace_hours: Mapped[float] = mapped_column(Float, default=3.0)

    subscriptions: Mapped[list["Subscription"]] = relationship(
        back_populates="profile"
    )


class Subscription(Base):
    __tablename__ = "subscriptions"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    anime_id: Mapped[int] = mapped_column(
        ForeignKey("anime.id", ondelete="CASCADE"), unique=True, index=True
    )
    enabled: Mapped[bool] = mapped_column(default=True)
    profile_id: Mapped[int] = mapped_column(
        ForeignKey("preference_profiles.id", ondelete="RESTRICT"), index=True
    )

    # The one group this show is followed from. Empty means unlocked, which only
    # makes sense together with ``allow_no_fansub``.
    fansub: Mapped[str] = mapped_column(String(128), default="")
    allow_no_fansub: Mapped[bool] = mapped_column(default=False)
    search_keywords: Mapped[list[str]] = mapped_column(JSON, default=list)
    must_include: Mapped[list[str]] = mapped_column(JSON, default=list)
    exclude_keywords: Mapped[list[str]] = mapped_column(JSON, default=list)
    use_subject_id: Mapped[bool] = mapped_column(default=True)
    resource_types: Mapped[list[str]] = mapped_column(JSON, default=lambda: ["动画"])
    profile_overrides: Mapped[dict[str, object] | None] = mapped_column(
        JSON, nullable=True
    )
    episode_offset_override: Mapped[int | None] = mapped_column(
        Integer, nullable=True
    )

    # A pending one-shot backfill: sweep this subscription from here once, then
    # clear the field. Holding a date rather than a boolean keeps "what is left
    # to do" in a single column, and keeps the season-length backfill out of the
    # shared global sweep window.
    backfill_after: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)

    # The earliest episode still missing, refreshed on every sweep. Cached on
    # the row because the worker already holds Bangumi's episode table, and
    # recomputing it per API request would put an upstream call behind the
    # subscription list.
    next_episode_index: Mapped[int | None] = mapped_column(Integer, nullable=True)
    next_episode_air_date: Mapped[datetime | None] = mapped_column(
        DateTime, nullable=True
    )

    cursor_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    last_checked_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    last_found_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    last_error: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_by: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )

    anime = relationship("Anime", back_populates="subscription")
    profile: Mapped[PreferenceProfile] = relationship(back_populates="subscriptions")
    created_by_user = relationship("User")
    episodes: Mapped[list["SubscriptionEpisode"]] = relationship(
        back_populates="subscription",
        cascade="all, delete-orphan",
        order_by="SubscriptionEpisode.created_at",
    )


class SubscriptionEpisode(Base):
    __tablename__ = "subscription_episodes"
    __table_args__ = (
        Index(
            "ix_subscription_episodes_subscription_episode_state",
            "subscription_id",
            "episode_index",
            "state",
        ),
        Index("ix_subscription_episodes_resource_id", "resource_id"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    subscription_id: Mapped[int] = mapped_column(
        ForeignKey("subscriptions.id", ondelete="CASCADE"), index=True
    )
    # ``None`` is intentional for resources that need manual episode review.
    episode_index: Mapped[int | None] = mapped_column(Integer, nullable=True)
    resource_id: Mapped[int] = mapped_column(Integer)
    resource_title: Mapped[str] = mapped_column(Text, default="")
    score: Mapped[float] = mapped_column(Float, default=0)
    attributes: Mapped[dict[str, object]] = mapped_column(JSON, default=dict)
    download_hash: Mapped[str | None] = mapped_column(String(40), nullable=True)
    state: Mapped[str] = mapped_column(String(32), default="candidate", index=True)
    reason: Mapped[str | None] = mapped_column(Text, nullable=True)
    first_seen_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, default=utcnow, onupdate=utcnow
    )

    subscription: Mapped[Subscription] = relationship(back_populates="episodes")
