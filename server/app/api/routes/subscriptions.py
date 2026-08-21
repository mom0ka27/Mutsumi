from __future__ import annotations

from datetime import UTC, datetime, timedelta
import logging
from typing import Any

from fastapi import APIRouter, Depends, HTTPException, Query, status
import httpx
from sqlalchemy import func, select, update
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.core.auth import get_current_user, get_session, require_download_permission
from app.core.config import config
from app.models import (
    Anime,
    Episode,
    PermissionGroup,
    PreferenceProfile,
    Subscription,
    SubscriptionEpisode,
    User,
)
from app.schemas import (
    FansubCandidateRead,
    PreferenceProfileCreate,
    PreferenceProfileRead,
    PreferenceProfileUpdate,
    SubscriptionCheckRead,
    SubscriptionCreate,
    SubscriptionEpisodeRead,
    SubscriptionPreviewRead,
    SubscriptionPreviewRequest,
    SubscriptionRead,
    SubscriptionUpdate,
)
from app.services.animegarden_service import AnimeGardenService
from app.services.bangumi_service import BangumiService
from app.services.subscription_engine import EpisodeInfo, next_expected_episode
from app.services.subscription_worker import (
    SubscriptionWorker,
    backfill_window_start,
    request_initial_check,
)


logger = logging.getLogger(__name__)
router = APIRouter(prefix="/subscriptions", tags=["subscriptions"])
profile_router = APIRouter(prefix="/preference-profiles", tags=["preference-profiles"])


@profile_router.get("", response_model=list[PreferenceProfileRead])
async def list_preference_profiles(
    _: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
):
    await _ensure_default_profile(session)
    await session.commit()
    return list(
        await session.scalars(
            select(PreferenceProfile).order_by(
                PreferenceProfile.is_default.desc(), PreferenceProfile.id
            )
        )
    )


@profile_router.post(
    "", response_model=PreferenceProfileRead, status_code=status.HTTP_201_CREATED
)
async def create_preference_profile(
    payload: PreferenceProfileCreate,
    _: User = Depends(require_download_permission),
    session: AsyncSession = Depends(get_session),
):
    _validate_profile_payload(payload)
    if payload.is_default:
        await session.execute(update(PreferenceProfile).values(is_default=False))
    profile = PreferenceProfile(**payload.model_dump())
    session.add(profile)
    await session.commit()
    await session.refresh(profile)
    return profile


@profile_router.put("/{profile_id}", response_model=PreferenceProfileRead)
async def update_preference_profile(
    profile_id: int,
    payload: PreferenceProfileUpdate,
    _: User = Depends(require_download_permission),
    session: AsyncSession = Depends(get_session),
):
    profile = await session.scalar(
        select(PreferenceProfile).where(PreferenceProfile.id == profile_id)
    )
    if profile is None:
        raise HTTPException(status_code=404, detail="Preference profile not found")
    changes = payload.model_dump(exclude_unset=True)
    _validate_profile_values(changes)
    if changes.get("is_default"):
        await session.execute(
            update(PreferenceProfile)
            .where(PreferenceProfile.id != profile_id)
            .values(is_default=False)
        )
    for key, value in changes.items():
        setattr(profile, key, value)
    await session.commit()
    await session.refresh(profile)
    return profile


@profile_router.delete("/{profile_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_preference_profile(
    profile_id: int,
    _: User = Depends(require_download_permission),
    session: AsyncSession = Depends(get_session),
):
    profile = await session.scalar(
        select(PreferenceProfile).where(PreferenceProfile.id == profile_id)
    )
    if profile is None:
        raise HTTPException(status_code=404, detail="Preference profile not found")
    references = await session.scalar(
        select(func.count())
        .select_from(Subscription)
        .where(Subscription.profile_id == profile_id)
    )
    if references:
        raise HTTPException(
            status_code=409,
            detail="Preference profile is used by a subscription",
        )
    was_default = profile.is_default
    await session.delete(profile)
    await session.flush()
    if was_default:
        replacement = await session.scalar(
            select(PreferenceProfile).order_by(PreferenceProfile.id)
        )
        if replacement:
            replacement.is_default = True
    await session.commit()


@router.get("", response_model=list[SubscriptionRead])
async def list_subscriptions(
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
):
    query = _subscription_query().order_by(Subscription.id)
    if current_user.permission_group != PermissionGroup.ADMIN:
        query = query.where(Subscription.created_by == current_user.id)
    subscriptions = list(await session.scalars(query))
    review_counts = await _needs_review_counts(
        session,
        [subscription.id for subscription in subscriptions],
    )
    return [
        _subscription_read(subscription, review_counts=review_counts)
        for subscription in subscriptions
    ]


@router.post("", response_model=SubscriptionRead, status_code=status.HTTP_201_CREATED)
async def create_subscription(
    payload: SubscriptionCreate,
    current_user: User = Depends(require_download_permission),
    session: AsyncSession = Depends(get_session),
):
    anime = await _resolve_or_create_anime(session, payload.bangumi_id)
    existing = await session.scalar(
        select(Subscription).where(Subscription.anime_id == anime.id)
    )
    if existing:
        raise HTTPException(status_code=409, detail="Anime is already subscribed")
    profile = await _resolve_profile(session, payload.profile_id)
    episodes = await _bangumi_episodes(anime)
    subscription = Subscription(
        **payload.model_dump(
            exclude={"profile_id", "bangumi_id", "backfill_aired"}
        ),
        anime_id=anime.id,
        profile_id=profile.id,
        created_by=current_user.id,
        backfill_after=(
            backfill_window_start(anime.air_date, episodes)
            if payload.backfill_aired
            else None
        ),
    )
    # Seeded here as well as in the worker: waiting up to a full sweep interval
    # would leave the new subscription with no expected date to show.
    (
        subscription.next_episode_index,
        subscription.next_episode_air_date,
    ) = next_expected_episode(
        episodes,
        (episode.index for episode in anime.episodes if episode.index is not None),
    )
    session.add(subscription)
    await session.commit()
    # Don't wait for the next sweep: following a show is a request to fetch it,
    # so the first check runs now. Queued on the worker, which owns the sweep
    # lock, rather than inline -- torrent metadata for a whole backfilled season
    # is far too slow to hold a request open.
    request_initial_check(subscription.id)
    loaded = await session.scalar(_subscription_query().where(Subscription.id == subscription.id))
    return _subscription_read(loaded or subscription)


@router.put("/{subscription_id}", response_model=SubscriptionRead)
async def update_subscription(
    subscription_id: int,
    payload: SubscriptionUpdate,
    current_user: User = Depends(require_download_permission),
    session: AsyncSession = Depends(get_session),
):
    subscription = await _get_manageable_subscription(
        session, subscription_id, current_user
    )
    changes = payload.model_dump(exclude_unset=True)
    if "profile_id" in changes:
        profile = await _resolve_profile(session, changes.pop("profile_id"))
        changes["profile_id"] = profile.id
    for key, value in changes.items():
        setattr(subscription, key, value)
    await session.commit()
    loaded = await session.scalar(_subscription_query().where(Subscription.id == subscription.id))
    return _subscription_read(loaded or subscription)


@router.delete("/{subscription_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_subscription(
    subscription_id: int,
    current_user: User = Depends(require_download_permission),
    session: AsyncSession = Depends(get_session),
):
    subscription = await _get_manageable_subscription(
        session, subscription_id, current_user
    )
    anime = subscription.anime
    await session.delete(subscription)
    await session.flush()
    if anime is not None and await _is_placeholder_anime(session, anime):
        # The Anime row exists only because this subscription created it: no
        # episodes, no torrent, nothing on disk. Removing it keeps the library
        # free of shows the user never actually acquired. Animes that do have
        # content are left alone -- only the subscription goes away.
        await session.delete(anime)
    await session.commit()


@router.post("/{subscription_id}/check", response_model=SubscriptionCheckRead)
async def check_subscription(
    subscription_id: int,
    current_user: User = Depends(require_download_permission),
    session: AsyncSession = Depends(get_session),
):
    subscription = await _get_manageable_subscription(
        session, subscription_id, current_user
    )
    worker = SubscriptionWorker()
    try:
        processed, found = await worker.check_subscription(subscription.id)
    except LookupError as error:
        raise HTTPException(status_code=404, detail=str(error)) from error
    except Exception as error:
        logger.exception("Manual subscription check failed id=%s", subscription_id)
        raise HTTPException(status_code=502, detail=f"检查订阅失败: {error}") from error
    loaded = await session.scalar(
        _subscription_query()
        .where(Subscription.id == subscription_id)
        .execution_options(populate_existing=True)
    )
    if loaded is None:
        raise HTTPException(status_code=404, detail="Subscription not found")
    return SubscriptionCheckRead(
        subscription=_subscription_read(loaded),
        processed=processed,
        found=found,
    )


@router.get(
    "/{subscription_id}/episodes",
    response_model=list[SubscriptionEpisodeRead],
)
async def list_subscription_episodes(
    subscription_id: int,
    state: str | None = Query(default=None),
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
):
    subscription = await _get_readable_subscription(
        session, subscription_id, current_user
    )
    query = select(SubscriptionEpisode).where(
        SubscriptionEpisode.subscription_id == subscription.id
    )
    if state:
        query = query.where(SubscriptionEpisode.state == state)
    return list(
        await session.scalars(
            query.order_by(
                SubscriptionEpisode.episode_index,
                SubscriptionEpisode.created_at,
            )
        )
    )


@router.post("/preview", response_model=SubscriptionPreviewRead)
async def preview_subscription(
    payload: SubscriptionPreviewRequest,
    _: User = Depends(require_download_permission),
    session: AsyncSession = Depends(get_session),
):
    # Preview runs before the subscription exists, so it must work for a show
    # that has no library row yet. An unsaved draft never creates one: the
    # in-memory Anime carries just what the engine reads.
    anime = await session.scalar(
        select(Anime)
        .options(selectinload(Anime.episodes))
        .where(Anime.bangumi_id == payload.bangumi_id)
    ) or Anime(id=0, bangumi_id=payload.bangumi_id, name="", name_cn="", episodes=[])
    profile = await _resolve_profile(session, payload.profile_id)
    try:
        result = await SubscriptionWorker().preview(
            anime=anime,
            profile=profile,
            draft=payload,
        )
    except Exception as error:
        logger.exception("Subscription preview failed bangumi_id=%s", payload.bangumi_id)
        raise HTTPException(status_code=502, detail=f"预览失败: {error}") from error
    return result


@router.get("/fansubs", response_model=list[FansubCandidateRead])
async def list_subscription_fansubs(
    bangumi_id: int = Query(gt=0),
    _: User = Depends(get_current_user),
):
    now = _utcnow()
    service = AnimeGardenService()
    display_names: dict[str, str] = {}
    counts: dict[str, int] = {}
    latest: dict[str, datetime | None] = {}
    resources, _ = await service.search_resources(
        page=1,
        page_size=100,
        after=now - timedelta(days=30),
        before=now,
        subjects=(bangumi_id,),
        types=("动画",),
    )
    for resource in resources:
        name = resource.fansub_name.strip()
        display_name = name or "(无字幕组)"
        key = display_name.casefold()
        display_names.setdefault(key, display_name)
        counts[key] = counts.get(key, 0) + 1
        current = latest.get(key)
        if resource.created_at and (current is None or resource.created_at > current):
            latest[key] = resource.created_at
    return [
        FansubCandidateRead(
            name=display_names[key],
            count=counts[key],
            latest_at=latest.get(key),
            is_no_fansub=display_names[key] == "(无字幕组)",
        )
        for key in sorted(
            counts, key=lambda item: (-counts[item], item)
        )
    ]


async def _resolve_or_create_anime(session: AsyncSession, bangumi_id: int) -> Anime:
    """Find the Anime for a Bangumi subject, creating a placeholder if needed.

    Subscribing to a show that has no episodes yet is the main use case, so the
    library row is created on demand from Bangumi metadata. It carries no
    ``download_hash`` and no episodes until the worker imports the first one.
    """
    anime = await session.scalar(
        select(Anime)
        .options(selectinload(Anime.episodes))
        .where(Anime.bangumi_id == bangumi_id)
    )
    if anime is not None:
        return anime

    try:
        subject = await BangumiService().get_subject(bangumi_id)
    except (httpx.HTTPError, ValueError) as error:
        logger.warning("Bangumi subject fetch failed id=%s: %s", bangumi_id, error)
        raise HTTPException(
            status_code=502,
            detail="无法从 Bangumi 获取番剧信息，请稍后重试",
        ) from error
    if subject is None:
        raise HTTPException(status_code=404, detail="Bangumi 上找不到这部番剧")

    anime = Anime(
        bangumi_id=subject.bangumi_id or bangumi_id,
        name=subject.name,
        name_cn=subject.name_cn,
        summary=subject.summary,
        image_url=subject.image_url,
        score=subject.score,
        episode_count=subject.episode_count,
        air_date=subject.air_date,
        rank=subject.rank,
        platform=subject.platform,
        tags=subject.tags,
        infobox=subject.infobox,
        # Initialized so later reads do not trigger a lazy load on a fresh
        # instance, which async SQLAlchemy cannot service.
        episodes=[],
    )
    session.add(anime)
    await session.flush()
    return anime


async def _bangumi_episodes(anime: Anime) -> list[EpisodeInfo]:
    """The episode table, or ``[]`` if Bangumi is unavailable.

    A subscription must be creatable even when the table cannot be read; the
    worker fills in what depends on it during its next sweep.
    """
    try:
        return await BangumiService().get_episodes(anime.bangumi_id)
    except (httpx.HTTPError, ValueError) as error:
        logger.warning(
            "Bangumi episode fetch failed id=%s: %s", anime.bangumi_id, error
        )
        return []


async def _is_placeholder_anime(session: AsyncSession, anime: Anime) -> bool:
    if anime.download_hash:
        return False
    episodes = await session.scalar(
        select(func.count()).select_from(Episode).where(Episode.anime_id == anime.id)
    )
    return not episodes


async def _ensure_default_profile(session: AsyncSession) -> PreferenceProfile:
    profile = await session.scalar(
        select(PreferenceProfile)
        .where(PreferenceProfile.is_default)
        .order_by(PreferenceProfile.id)
    )
    if profile:
        return profile
    profile = PreferenceProfile(
        name="默认",
        is_default=True,
        language_mode="简",
        language_unknown="accept",
        must_include=[],
        exclude_tokens=[],
        prefer_resolution=["1080p", "2160p"],
        prefer_codec=["av1", "hevc", "avc"],
        prefer_subtitle=["日", "无"],
        prefer_bitdepth=["10bit", "8bit"],
        weights={"fansub": 45, "resolution": 22, "codec": 15, "subtitle": 12, "bitdepth": 6},
        neutral_score=0.5,
        accept_now_score=0.85,
        grace_hours=3.0,
    )
    session.add(profile)
    await session.flush()
    return profile


async def _resolve_profile(
    session: AsyncSession,
    profile_id: int | None,
) -> PreferenceProfile:
    if profile_id is None:
        return await _ensure_default_profile(session)
    profile = await session.scalar(
        select(PreferenceProfile).where(PreferenceProfile.id == profile_id)
    )
    if profile is None:
        raise HTTPException(status_code=404, detail="Preference profile not found")
    return profile


def _subscription_query():
    return select(Subscription).options(
        selectinload(Subscription.anime).selectinload(Anime.episodes),
        selectinload(Subscription.profile),
    )


async def _needs_review_counts(
    session: AsyncSession,
    subscription_ids: list[int],
) -> dict[int, int]:
    """One grouped query for the whole list, rather than a count per row."""
    if not subscription_ids:
        return {}
    rows = await session.execute(
        select(
            SubscriptionEpisode.subscription_id,
            func.count(SubscriptionEpisode.id),
        )
        .where(
            SubscriptionEpisode.subscription_id.in_(subscription_ids),
            SubscriptionEpisode.state == "needs_review",
        )
        .group_by(SubscriptionEpisode.subscription_id)
    )
    return {subscription_id: count for subscription_id, count in rows}


async def _get_readable_subscription(
    session: AsyncSession,
    subscription_id: int,
    current_user: User,
) -> Subscription:
    subscription = await session.scalar(
        _subscription_query().where(Subscription.id == subscription_id)
    )
    if subscription is None:
        raise HTTPException(status_code=404, detail="Subscription not found")
    if (
        current_user.permission_group != PermissionGroup.ADMIN
        and subscription.created_by != current_user.id
    ):
        raise HTTPException(status_code=404, detail="Subscription not found")
    return subscription


async def _get_manageable_subscription(
    session: AsyncSession,
    subscription_id: int,
    current_user: User,
) -> Subscription:
    return await _get_readable_subscription(session, subscription_id, current_user)


def _subscription_read(
    subscription: Subscription,
    review_counts: dict[int, int] | None = None,
) -> SubscriptionRead:
    anime = subscription.anime
    last_checked = subscription.last_checked_at
    interval_minutes = _subscription_interval_minutes()
    next_check = (
        last_checked + timedelta(minutes=interval_minutes)
        if last_checked is not None and subscription.enabled
        else None
    )
    return SubscriptionRead(
        id=subscription.id,
        anime_id=subscription.anime_id,
        bangumi_id=anime.bangumi_id if anime else 0,
        anime_name=anime.name if anime else "",
        anime_name_cn=anime.name_cn if anime else "",
        image_url=anime.image_url if anime else "",
        enabled=subscription.enabled,
        profile_id=subscription.profile_id,
        fansubs=list(subscription.fansubs or []),
        allow_no_fansub=subscription.allow_no_fansub,
        search_keywords=list(subscription.search_keywords or []),
        must_include=list(subscription.must_include or []),
        exclude_keywords=list(subscription.exclude_keywords or []),
        use_subject_id=subscription.use_subject_id,
        resource_types=list(subscription.resource_types or []),
        profile_overrides=subscription.profile_overrides,
        episode_offset_override=subscription.episode_offset_override,
        cursor_at=subscription.cursor_at,
        backfill_after=subscription.backfill_after,
        last_checked_at=subscription.last_checked_at,
        last_found_at=subscription.last_found_at,
        last_error=subscription.last_error,
        created_by=subscription.created_by,
        next_check_at=next_check,
        episode_count=anime.episode_count if anime else 0,
        owned_episode_count=len(anime.episodes) if anime else 0,
        next_episode_index=subscription.next_episode_index,
        next_episode_air_date=subscription.next_episode_air_date,
        needs_review_count=(review_counts or {}).get(subscription.id, 0),
    )


def _subscription_interval_minutes() -> int:
    value = config.get("subscription")
    try:
        return max(1, int(value.get("interval_minutes", 15))) if isinstance(value, dict) else 15
    except (TypeError, ValueError):
        return 15


def _validate_profile_payload(payload: PreferenceProfileCreate) -> None:
    _validate_profile_values(payload.model_dump())


def _validate_profile_values(values: dict[str, Any]) -> None:
    if "language_mode" in values and values["language_mode"] not in {"any", "简", "繁"}:
        raise HTTPException(status_code=422, detail="language_mode 必须是 any、简或繁")
    if "language_unknown" in values and values["language_unknown"] not in {"accept", "reject"}:
        raise HTTPException(status_code=422, detail="language_unknown 必须是 accept 或 reject")


def _utcnow() -> datetime:
    return datetime.now(UTC).replace(tzinfo=None)
