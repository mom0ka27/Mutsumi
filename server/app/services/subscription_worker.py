from __future__ import annotations

import asyncio
from collections import defaultdict
from datetime import UTC, date, datetime, timedelta
import logging
from pathlib import Path
import random
from typing import Any

import httpx
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker
from sqlalchemy.orm import selectinload

from app.core.config import config
from app.db.session import AsyncSessionLocal
from app.models import Anime, Episode, PreferenceProfile, Subscription, SubscriptionEpisode
from app.schemas.qbittorrent import QBittorrentTorrentDownload
from app.services.animegarden_service import AnimeGardenResource, AnimeGardenService
from app.services.bangumi_service import BangumiService
from app.api.routes.qbittorrent import (
    download_torrent_files,
    fetch_torrent_metadata_files,
)
from app.core.qbittorrent_error import QBittorrentError
from app.services.subscription_engine import (
    EpisodeParseResult,
    ProfileValues,
    ResourceEvaluation,
    evaluate_resource,
    next_expected_episode,
    parse_episode_index,
    profile_values,
    resource_matches_subscription,
    subscription_rules,
)
from app.services.storage_service import VIDEO_EXTENSIONS


logger = logging.getLogger(__name__)
_sweep_lock = asyncio.Lock()
_VIDEO_MIN_SIZE = 10 * 1024 * 1024


class SubscriptionSweepAborted(RuntimeError):
    """The upstream download service was unavailable; keep the cursor unchanged."""


class SubscriptionWorker:
    def __init__(
        self,
        *,
        anime_garden: AnimeGardenService | None = None,
        bangumi: BangumiService | None = None,
        session_factory: async_sessionmaker[AsyncSession] = AsyncSessionLocal,
    ) -> None:
        self.anime_garden = anime_garden or AnimeGardenService()
        self.bangumi = bangumi or BangumiService()
        self.session_factory = session_factory

    async def run_sweep(self, *, now: datetime | None = None) -> dict[str, int | bool]:
        async with _sweep_lock:
            return await self._run_sweep(now=now or _utcnow())

    async def check_subscription(
        self,
        subscription_id: int,
        *,
        now: datetime | None = None,
    ) -> tuple[int, int]:
        """Run a targeted check used by the manual API action."""
        async with _sweep_lock:
            current_time = now or _utcnow()
            async with self.session_factory() as session:
                subscription = await _load_subscription(session, subscription_id)
                if subscription is None:
                    raise LookupError("Subscription not found")
                resources = await self._fetch_targeted_resources(
                    subscription,
                    current_time,
                )
                processed, found = await self._process_subscription(
                    session,
                    subscription,
                    resources,
                    current_time,
                )
                subscription.last_checked_at = current_time
                subscription.last_error = None
                if found:
                    subscription.last_found_at = current_time
                if resources:
                    latest = _latest_resource_time(resources)
                    if latest and (subscription.cursor_at is None or latest > subscription.cursor_at):
                        subscription.cursor_at = latest
                await session.commit()
                return processed, found

    async def preview(
        self,
        *,
        anime: Anime,
        profile: PreferenceProfile,
        draft: Any,
        now: datetime | None = None,
    ) -> dict[str, Any]:
        current_time = now or _utcnow()
        if not anime.name and not anime.id:
            # A draft for a show with no library row: fill the transient Anime
            # so season inference and title fallback matching behave as they
            # will once the subscription exists.
            subject = await self.bangumi.get_subject(anime.bangumi_id)
            if subject is not None:
                anime.name = subject.name
                anime.name_cn = subject.name_cn
                anime.episode_count = subject.episode_count
        resources = await self._fetch_draft_resources(anime, draft, current_time)
        episodes = await self.bangumi.get_episodes(anime.bangumi_id)
        rules = subscription_rules(draft, anime)
        values = profile_values(profile, getattr(draft, "profile_overrides", None))
        existing_indices = {episode.index for episode in anime.episodes}
        rows: list[dict[str, Any]] = []
        accepted_count = 0
        selected_by_episode: dict[int, tuple[float, int]] = {}

        for resource in resources:
            matches, match_reason = resource_matches_subscription(resource, rules)
            if not matches:
                rows.append(
                    _preview_row(
                        resource,
                        None,
                        ResourceEvaluation(
                            accepted=False,
                            score=0,
                            reason=match_reason,
                            attributes={"resource_type": resource.type},
                            component_scores={},
                        ),
                        "skipped",
                    )
                )
                continue
            evaluation = evaluate_resource(resource, values, rules)
            if not evaluation.accepted:
                rows.append(_preview_row(resource, None, evaluation, "skipped"))
                continue
            accepted_count += 1
            parsed = parse_episode_index(
                resource.title,
                episodes,
                resource.created_at,
                episode_offset_override=rules.episode_offset_override,
                anime_name=anime.name,
            )
            if parsed.index is None:
                rows.append(
                    _preview_row(
                        resource,
                        parsed,
                        evaluation,
                        "deferred" if parsed.deferred else "needs_review",
                    )
                )
                continue
            if parsed.index in existing_indices:
                rows.append(
                    _preview_row(
                        resource,
                        parsed,
                        evaluation,
                        "skipped",
                        reason="该集已存在",
                    )
                )
                continue
            row_index = len(rows)
            rows.append(_preview_row(resource, parsed, evaluation, "candidate"))
            current = selected_by_episode.get(parsed.index)
            if current is None or evaluation.score > current[0]:
                selected_by_episode[parsed.index] = (evaluation.score, row_index)

        for _, row_index in selected_by_episode.values():
            rows[row_index]["selected"] = True
        for row in rows:
            if row["state"] == "candidate" and not row["selected"]:
                row["reason"] = "同集候选得分更高"
        rows.sort(
            key=lambda row: (
                row["episode_index"] is None,
                row["episode_index"] or 0,
                -row["score"],
            )
        )
        return {
            "anime_id": anime.id,
            "bangumi_id": anime.bangumi_id,
            "resource_count": len(resources),
            "accepted_count": accepted_count,
            "candidates": rows,
        }

    async def _run_sweep(self, *, now: datetime) -> dict[str, int | bool]:
        async with self.session_factory() as session:
            subscriptions = list(
                await session.scalars(
                    select(Subscription)
                    .options(
                        selectinload(Subscription.anime).selectinload(Anime.episodes),
                        selectinload(Subscription.profile),
                    )
                    .where(Subscription.enabled)
                    .order_by(Subscription.id)
                )
            )
            if not subscriptions:
                return {"subscriptions": 0, "resources": 0, "found": 0, "aborted": False}

            start = min(
                (
                    subscription.cursor_at
                    or now
                    - timedelta(
                        days=_config_int("cold_start_days", 7),
                    )
                    for subscription in subscriptions
                ),
                default=now,
            )
            resources = await self._fetch_global_resources(start, now)
            processed = 0
            found = 0
            try:
                for subscription in subscriptions:
                    try:
                        async with session.begin_nested():
                            sub_resources = resources
                            if subscription.backfill_after is not None:
                                # A one-shot catch-up for a show joined
                                # mid-season. It stays a targeted query so the
                                # season-long window never widens the shared
                                # global sweep.
                                backfilled = await self._fetch_backfill_resources(
                                    subscription,
                                    now,
                                )
                                sub_resources = backfilled + resources
                            sub_processed, sub_found = await self._process_subscription(
                                session,
                                subscription,
                                sub_resources,
                                now,
                            )
                            subscription.backfill_after = None
                        processed += sub_processed
                        found += sub_found
                        subscription.last_checked_at = now
                        subscription.last_error = None
                        if sub_found:
                            subscription.last_found_at = now
                        latest = _latest_resource_time(
                            [
                                resource
                                for resource in sub_resources
                                if _resource_after_cursor(resource, subscription.cursor_at, now)
                            ]
                        )
                        if latest and (subscription.cursor_at is None or latest > subscription.cursor_at):
                            subscription.cursor_at = latest
                    except SubscriptionSweepAborted:
                        raise
                    except Exception as error:
                        subscription.last_error = str(error)
                        logger.exception(
                            "Subscription %s failed during sweep",
                            subscription.id,
                        )
                await session.commit()
            except SubscriptionSweepAborted as error:
                await session.rollback()
                logger.warning("Subscription sweep aborted: %s", error)
                return {
                    "subscriptions": len(subscriptions),
                    "resources": len(resources),
                    "found": found,
                    "aborted": True,
                }
            return {
                "subscriptions": len(subscriptions),
                "resources": len(resources),
                "found": found,
                "aborted": False,
            }

    async def _fetch_global_resources(
        self,
        after: datetime,
        before: datetime,
    ) -> list[AnimeGardenResource]:
        resources: dict[int, AnimeGardenResource] = {}
        max_pages = _config_int("max_pages_per_sweep", 5)
        for page in range(1, max_pages + 1):
            page_resources, complete = await self.anime_garden.search_resources(
                page=page,
                page_size=100,
                after=after,
                before=before,
                types=("动画",),
            )
            for resource in page_resources:
                resources[resource.id] = resource
            if complete:
                break
        return sorted(resources.values(), key=_resource_sort_key)

    async def _fetch_targeted_resources(
        self,
        subscription: Subscription,
        now: datetime,
    ) -> list[AnimeGardenResource]:
        anime = subscription.anime
        after = subscription.cursor_at or now - timedelta(days=_config_int("cold_start_days", 7))
        subjects = _subjects_for(anime, subscription.use_subject_id)
        # ``subjects`` and ``search`` are ANDed upstream, and resource titles
        # rarely carry the full Bangumi name, so the name is only a fallback for
        # when the subject id is unavailable.
        search = tuple(subscription.search_keywords or ())
        if not search and not subjects and anime:
            search = (anime.name,)
        return await self._fetch_resources(
            after=after,
            before=now,
            subjects=subjects,
            search=search,
            types=tuple(subscription.resource_types or ("动画",)),
        )

    async def _fetch_backfill_resources(
        self,
        subscription: Subscription,
        now: datetime,
    ) -> list[AnimeGardenResource]:
        anime = subscription.anime
        return await self._fetch_resources(
            after=_naive_utc(subscription.backfill_after or now),
            before=now,
            subjects=_subjects_for(anime, subscription.use_subject_id),
            search=tuple(subscription.search_keywords or ()),
            types=tuple(subscription.resource_types or ("动画",)),
        )

    async def _fetch_draft_resources(
        self,
        anime: Anime,
        draft: Any,
        now: datetime,
    ) -> list[AnimeGardenResource]:
        subjects = _subjects_for(anime, getattr(draft, "use_subject_id", True))
        search = tuple(getattr(draft, "search_keywords", None) or ())
        if not search and not subjects:
            search = (anime.name,)
        return await self._fetch_resources(
            after=now - timedelta(days=_config_int("cold_start_days", 7)),
            before=now,
            subjects=subjects,
            search=search,
            types=tuple(getattr(draft, "resource_types", None) or ("动画",)),
        )

    async def _fetch_resources(
        self,
        *,
        after: datetime,
        before: datetime,
        subjects: tuple[int, ...] = (),
        search: tuple[str, ...] = (),
        types: tuple[str, ...] = ("动画",),
    ) -> list[AnimeGardenResource]:
        resources: dict[int, AnimeGardenResource] = {}
        for page in range(1, _config_int("max_pages_per_sweep", 5) + 1):
            page_resources, complete = await self.anime_garden.search_resources(
                page=page,
                page_size=100,
                after=after,
                before=before,
                subjects=subjects,
                search=search,
                types=types,
            )
            for resource in page_resources:
                resources[resource.id] = resource
            if complete:
                break
        return sorted(resources.values(), key=_resource_sort_key)

    async def _process_subscription(
        self,
        session: AsyncSession,
        subscription: Subscription,
        resources: list[AnimeGardenResource],
        now: datetime,
    ) -> tuple[int, int]:
        anime = subscription.anime
        if anime is None:
            return 0, 0
        episodes = await self.bangumi.get_episodes(anime.bangumi_id)
        values = profile_values(subscription.profile, subscription.profile_overrides)
        rules = subscription_rules(subscription, anime)
        existing_indices = {
            episode.index
            for episode in anime.episodes
            if episode.index is not None
        }
        existing_resource_ids = set(
            await session.scalars(
                select(SubscriptionEpisode.resource_id).where(
                    SubscriptionEpisode.subscription_id == subscription.id
                )
            )
        )
        await self._retry_deferred(session, subscription, episodes, anime)
        processed = 0
        found = 0
        for resource in resources:
            if resource.id in existing_resource_ids:
                continue
            if not _resource_after_cursor(resource, subscription.cursor_at, now):
                continue
            matches, _ = resource_matches_subscription(resource, rules)
            if not matches:
                continue
            processed += 1
            evaluation = evaluate_resource(resource, values, rules)
            if not evaluation.accepted:
                session.add(
                    _ledger_entry(
                        subscription,
                        resource,
                        evaluation,
                        episode_index=None,
                        state="skipped",
                    )
                )
                continue
            found += 1
            parsed = parse_episode_index(
                resource.title,
                episodes,
                resource.created_at,
                episode_offset_override=rules.episode_offset_override,
                anime_name=anime.name,
            )
            if parsed.index is None:
                session.add(
                    _ledger_entry(
                        subscription,
                        resource,
                        evaluation,
                        episode_index=None,
                        # ``deferred`` waits for Bangumi to publish the episode
                        # table; ``needs_review`` waits for a human. Confusing
                        # the two would strand the first episode of every show
                        # subscribed before it aired.
                        state="deferred" if parsed.deferred else "needs_review",
                        reason=parsed.reason,
                        parsed=parsed,
                    )
                )
                continue
            if parsed.index in existing_indices:
                session.add(
                    _ledger_entry(
                        subscription,
                        resource,
                        evaluation,
                        episode_index=parsed.index,
                        state="skipped",
                        reason="该集已存在",
                        parsed=parsed,
                    )
                )
                continue
            session.add(
                _ledger_entry(
                    subscription,
                    resource,
                    evaluation,
                    episode_index=parsed.index,
                    state="candidate",
                    parsed=parsed,
                )
            )
        await session.flush()
        await self._settle_candidates(
            session,
            subscription,
            values,
            existing_indices,
            now,
        )
        # After settling, ``existing_indices`` includes whatever was just
        # imported, so the cached "next episode" reflects this sweep.
        (
            subscription.next_episode_index,
            subscription.next_episode_air_date,
        ) = next_expected_episode(episodes, existing_indices)
        return processed, found

    async def _retry_deferred(
        self,
        session: AsyncSession,
        subscription: Subscription,
        episodes: list[Any],
        anime: Anime,
    ) -> None:
        """Re-resolve rows that were waiting for Bangumi's episode table.

        They already passed the hard filters and were scored; the only thing
        missing was the ep/sort ranges. Once Bangumi publishes them, the row
        rejoins the candidate pool with its original ``first_seen_at``, so the
        waiting window is not restarted.
        """
        if not episodes:
            return
        deferred = list(
            await session.scalars(
                select(SubscriptionEpisode).where(
                    SubscriptionEpisode.subscription_id == subscription.id,
                    SubscriptionEpisode.state == "deferred",
                )
            )
        )
        for row in deferred:
            attributes = row.attributes or {}
            parsed = parse_episode_index(
                row.resource_title,
                episodes,
                attributes.get("created_at") or row.first_seen_at,
                episode_offset_override=subscription.episode_offset_override,
                anime_name=anime.name,
            )
            if parsed.deferred:
                continue
            row.episode_index = parsed.index
            row.state = "candidate" if parsed.index is not None else "needs_review"
            row.reason = parsed.reason
            row.attributes = {
                **attributes,
                "episode_parse": _episode_parse_attributes(parsed),
            }

    async def _settle_candidates(
        self,
        session: AsyncSession,
        subscription: Subscription,
        profile: ProfileValues,
        existing_indices: set[int],
        now: datetime,
    ) -> None:
        candidates = list(
            await session.scalars(
                select(SubscriptionEpisode)
                .where(
                    SubscriptionEpisode.subscription_id == subscription.id,
                    SubscriptionEpisode.state == "candidate",
                    SubscriptionEpisode.episode_index.is_not(None),
                )
                .order_by(SubscriptionEpisode.created_at, SubscriptionEpisode.id)
            )
        )
        grouped: dict[int, list[SubscriptionEpisode]] = defaultdict(list)
        for candidate in candidates:
            if candidate.episode_index is not None:
                grouped[candidate.episode_index].append(candidate)

        for episode_index, group in grouped.items():
            if episode_index in existing_indices:
                for candidate in group:
                    candidate.state = "skipped"
                    candidate.reason = "该集已存在"
                continue
            earliest = min(candidate.first_seen_at for candidate in group)
            age_hours = (now - _naive_utc(earliest)).total_seconds() / 3600
            immediate = any(candidate.score >= profile.accept_now_score for candidate in group)
            if not immediate and age_hours < profile.grace_hours:
                continue
            winner = max(
                group,
                key=lambda candidate: (
                    candidate.score,
                    -_naive_utc(candidate.first_seen_at).timestamp(),
                ),
            )
            for candidate in group:
                if candidate is not winner:
                    candidate.state = "skipped"
                    candidate.reason = "同集候选得分更高"
            await self._deliver_candidate(
                session,
                subscription,
                winner,
                existing_indices,
            )

    async def _deliver_candidate(
        self,
        session: AsyncSession,
        subscription: Subscription,
        candidate: SubscriptionEpisode,
        existing_indices: set[int],
    ) -> None:
        if not _config_bool("auto_import", True):
            candidate.state = "matched"
            candidate.reason = "观察模式，不自动下载"
            return
        if not subscription.anime or candidate.episode_index is None:
            candidate.state = "needs_review"
            candidate.reason = "订阅缺少番剧或集数"
            return
        resource = await _resource_for_candidate(candidate)
        if resource is None:
            candidate.state = "failed"
            candidate.reason = "台账缺少下载链接"
            return

        try:
            files = await fetch_torrent_metadata_files(resource.download_link)
        except (QBittorrentError, httpx.HTTPError) as error:
            raise SubscriptionSweepAborted(str(error)) from error
        videos = [
            file
            for file in files
            if Path(file.name).suffix.lower() in VIDEO_EXTENSIONS
            and file.size > _VIDEO_MIN_SIZE
        ]
        if len(videos) != 1:
            candidate.state = "needs_review"
            candidate.reason = (
                "未找到唯一视频文件"
                if not videos
                else "种子包含多个视频文件，需人工匹配"
            )
            return

        candidate.state = "downloading"
        try:
            result = await download_torrent_files(
                QBittorrentTorrentDownload(
                    source=resource.download_link,
                    filenames=[videos[0].name],
                ),
                None,
            )
        except (QBittorrentError, httpx.HTTPError) as error:
            raise SubscriptionSweepAborted(str(error)) from error

        candidate.download_hash = result.hash or None
        episode = await session.scalar(
            select(Episode).where(
                Episode.anime_id == subscription.anime.id,
                Episode.index == candidate.episode_index,
            )
        )
        if episode is None:
            episode_parse = candidate.attributes.get("episode_parse") or {}
            episode = Episode(
                anime_id=subscription.anime.id,
                index=candidate.episode_index,
                name=str(
                    episode_parse.get("name_cn")
                    or episode_parse.get("name")
                    or ""
                ),
                filename=videos[0].name,
                download_hash=result.hash or None,
            )
            session.add(episode)
        candidate.state = "imported"
        candidate.reason = "已添加下载并建立 Episode 台账"
        existing_indices.add(candidate.episode_index)


async def _resource_for_candidate(candidate: SubscriptionEpisode) -> AnimeGardenResource | None:
    # The ledger deliberately stores attributes rather than the complete
    # upstream object. The worker puts the download link into attributes when
    # it creates a candidate, so retries remain possible without another feed
    # query.
    data = candidate.attributes or {}
    link = data.get("download_link")
    if not link:
        return None
    return AnimeGardenResource(
        id=candidate.resource_id,
        provider="",
        provider_id="",
        title=candidate.resource_title,
        type=str(data.get("resource_type") or "动画"),
        magnet=str(data.get("magnet") or link),
        tracker=str(data.get("tracker") or ""),
        size=int(data.get("size") or 0),
        fansub_name=str(data.get("fansub") or ""),
        publisher_name="",
        created_at=_datetime(data.get("created_at")),
        subject_ids=frozenset(),
    )


def _ledger_entry(
    subscription: Subscription,
    resource: AnimeGardenResource,
    evaluation: ResourceEvaluation,
    *,
    episode_index: int | None,
    state: str,
    reason: str | None = None,
    parsed: EpisodeParseResult | None = None,
) -> SubscriptionEpisode:
    attributes = dict(evaluation.attributes)
    attributes.update(
        {
            "download_link": resource.download_link,
            "magnet": resource.magnet,
            "tracker": resource.tracker,
            "size": resource.size,
            "created_at": resource.created_at.isoformat() if resource.created_at else None,
            "provider": resource.provider,
            "provider_id": resource.provider_id,
        }
    )
    if parsed is not None:
        attributes["episode_parse"] = _episode_parse_attributes(parsed)
    return SubscriptionEpisode(
        subscription_id=subscription.id,
        episode_index=episode_index,
        resource_id=resource.id,
        resource_title=resource.title,
        score=evaluation.score,
        attributes=attributes,
        state=state,
        reason=reason or evaluation.reason,
        first_seen_at=_naive_utc(resource.created_at) if resource.created_at else _utcnow(),
    )


def _episode_parse_attributes(parsed: EpisodeParseResult) -> dict[str, Any]:
    return {
        "raw_number": parsed.raw_number,
        "season_number": parsed.season_number,
        "reason": parsed.reason,
        "deferred": parsed.deferred,
        "bangumi_ep": parsed.episode.ep if parsed.episode else None,
        "bangumi_sort": parsed.episode.sort if parsed.episode else None,
        "name": parsed.episode.name if parsed.episode else "",
        "name_cn": parsed.episode.name_cn if parsed.episode else "",
    }


def _preview_row(
    resource: AnimeGardenResource,
    parsed: EpisodeParseResult | None,
    evaluation: ResourceEvaluation,
    state: str,
    *,
    reason: str | None = None,
) -> dict[str, Any]:
    attributes = dict(evaluation.attributes)
    attributes["episode_parse"] = {
        "raw_number": parsed.raw_number if parsed else None,
        "reason": parsed.reason if parsed else None,
    }
    return {
        "episode_index": parsed.index if parsed else None,
        "resource_id": resource.id,
        "resource_title": resource.title,
        "fansub": resource.fansub_name,
        "score": evaluation.score,
        "state": state,
        "reason": reason or parsed.reason if parsed and state == "needs_review" else reason or evaluation.reason,
        "attributes": attributes,
        "selected": False,
        "created_at": resource.created_at,
    }


async def _load_subscription(
    session: AsyncSession,
    subscription_id: int,
) -> Subscription | None:
    return await session.scalar(
        select(Subscription)
        .options(
            selectinload(Subscription.anime).selectinload(Anime.episodes),
            selectinload(Subscription.profile),
        )
        .where(Subscription.id == subscription_id)
    )


def _subjects_for(anime: Anime | None, use_subject_id: bool) -> tuple[int, ...]:
    bangumi_id = int(getattr(anime, "bangumi_id", 0) or 0) if anime else 0
    return (bangumi_id,) if use_subject_id and bangumi_id else ()


def _resource_sort_key(resource: AnimeGardenResource) -> tuple[datetime, int]:
    return (_naive_utc(resource.created_at) if resource.created_at else datetime.min, resource.id)


def _latest_resource_time(resources: list[AnimeGardenResource]) -> datetime | None:
    values = [_naive_utc(resource.created_at) for resource in resources if resource.created_at]
    return max(values) if values else None


def _resource_after_cursor(
    resource: AnimeGardenResource,
    cursor: datetime | None,
    now: datetime,
) -> bool:
    if resource.created_at is None:
        return True
    created = _naive_utc(resource.created_at)
    return cursor is None or created > _naive_utc(cursor)


def _datetime(value: Any) -> datetime | None:
    if value is None:
        return None
    if isinstance(value, datetime):
        return _naive_utc(value)
    if isinstance(value, date):
        return datetime.combine(value, datetime.min.time())
    try:
        return _naive_utc(datetime.fromisoformat(str(value).replace("Z", "+00:00")))
    except ValueError:
        return None


def _naive_utc(value: datetime) -> datetime:
    if value.tzinfo:
        return value.astimezone(UTC).replace(tzinfo=None)
    return value


def _utcnow() -> datetime:
    return datetime.now(UTC).replace(tzinfo=None)


def _subscription_config() -> dict[str, Any]:
    value = config.get("subscription")
    return value if isinstance(value, dict) else {}


def _config_int(key: str, default: int) -> int:
    try:
        return max(1, int(_subscription_config().get(key, default)))
    except (TypeError, ValueError):
        return default


def _config_bool(key: str, default: bool) -> bool:
    value = _subscription_config().get(key, default)
    return bool(value)


async def subscription_worker_loop(worker: SubscriptionWorker | None = None) -> None:
    worker = worker or SubscriptionWorker()
    interval_minutes = max(1, _config_int("interval_minutes", 15))
    first_run = True
    while True:
        interval = interval_minutes * 60
        if first_run:
            first_run = False
            interval += random.uniform(0, min(60, interval))
        else:
            interval += random.uniform(0, min(60, interval / 10))
        await asyncio.sleep(interval)
        try:
            result = await worker.run_sweep()
            logger.info("Subscription sweep finished: %s", result)
        except asyncio.CancelledError:
            raise
        except Exception:
            logger.exception("Subscription worker failed")
