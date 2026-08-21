from __future__ import annotations

from datetime import UTC, datetime, timedelta
import logging
from typing import Any

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import func, select, update
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.core.auth import get_current_user, get_session, require_download_permission
from app.core.config import config
from app.models import (
    Anime,
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
from app.services.subscription_worker import SubscriptionWorker


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
    return [_subscription_read(subscription) for subscription in subscriptions]


@router.post("", response_model=SubscriptionRead, status_code=status.HTTP_201_CREATED)
async def create_subscription(
    payload: SubscriptionCreate,
    current_user: User = Depends(require_download_permission),
    session: AsyncSession = Depends(get_session),
):
    anime = await session.scalar(select(Anime).where(Anime.id == payload.anime_id))
    if anime is None:
        raise HTTPException(status_code=404, detail="Anime not found")
    existing = await session.scalar(
        select(Subscription).where(Subscription.anime_id == payload.anime_id)
    )
    if existing:
        raise HTTPException(status_code=409, detail="Anime is already subscribed")
    profile = await _resolve_profile(session, payload.profile_id)
    subscription = Subscription(
        **payload.model_dump(exclude={"profile_id", "anime_id"}),
        anime_id=anime.id,
        profile_id=profile.id,
        created_by=current_user.id,
    )
    session.add(subscription)
    await session.commit()
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
    await session.delete(subscription)
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
    anime = await session.scalar(
        select(Anime)
        .options(selectinload(Anime.episodes))
        .where(Anime.id == payload.anime_id)
    )
    if anime is None:
        raise HTTPException(status_code=404, detail="Anime not found")
    profile = await _resolve_profile(session, payload.profile_id)
    try:
        result = await SubscriptionWorker().preview(
            anime=anime,
            profile=profile,
            draft=payload,
        )
    except Exception as error:
        logger.exception("Subscription preview failed anime=%s", payload.anime_id)
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
        selectinload(Subscription.anime),
        selectinload(Subscription.profile),
    )


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


def _subscription_read(subscription: Subscription) -> SubscriptionRead:
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
        last_checked_at=subscription.last_checked_at,
        last_found_at=subscription.last_found_at,
        last_error=subscription.last_error,
        created_by=subscription.created_by,
        next_check_at=next_check,
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
