from __future__ import annotations

import asyncio
from collections import defaultdict
from dataclasses import dataclass
from datetime import UTC, date, datetime
import logging
from pathlib import Path
import random
from types import SimpleNamespace
from typing import Any

import httpx
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker
from sqlalchemy.orm import selectinload

from app.core.config import config
from app.db.session import AsyncSessionLocal
from app.models import Anime, Episode, PreferenceProfile, Subscription, SubscriptionEpisode
from app.schemas.qbittorrent import QBittorrentTorrentDownload
from app.services.animegarden_service import (
    MAX_PAGE_SIZE,
    AnimeGardenResource,
    AnimeGardenService,
)
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
    aired_episode_indices,
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


@dataclass(frozen=True)
class _Query:
    """One upstream feed query. Terms within it are ANDed by the API."""

    subjects: tuple[int, ...] = ()
    search: tuple[str, ...] = ()


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
                resources = await self._fetch_subject_history(
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
                await session.commit()
                return processed, found

    async def run_initial_check(self, subscription_id: int) -> None:
        """The first pass over a brand-new subscription.

        Nobody is waiting on the result, so a failure is recorded on the row
        instead of raised: an unreported failure here is exactly what leaves a
        card sitting at 等待资源 with no explanation.
        """
        try:
            processed, found = await self.check_subscription(subscription_id)
        except LookupError:
            return  # Unsubscribed again before the loop got to it.
        except Exception as error:
            logger.exception("Initial subscription check failed id=%s", subscription_id)
            await self._record_error(subscription_id, error)
            return
        logger.info(
            "Initial subscription check done id=%s processed=%s found=%s",
            subscription_id,
            processed,
            found,
        )

    async def _record_error(self, subscription_id: int, error: Exception) -> None:
        async with self.session_factory() as session:
            subscription = await session.get(Subscription, subscription_id)
            if subscription is None:
                return
            subscription.last_error = str(error)
            subscription.last_checked_at = _utcnow()
            await session.commit()

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
            # so season inference, the backfill window, and title fallback
            # matching behave as they will once the subscription exists.
            subject = await self.bangumi.get_subject(anime.bangumi_id)
            if subject is not None:
                anime.name = subject.name
                anime.name_cn = subject.name_cn
                anime.episode_count = subject.episode_count
                anime.air_date = subject.air_date
                anime.aliases = list(subject.aliases)
        episodes = await self.bangumi.get_episodes(anime.bangumi_id)
        rules = subscription_rules(draft, anime)
        values = profile_values(profile, getattr(draft, "profile_overrides", None))
        existing_indices = {
            episode.index for episode in anime.episodes if episode.index is not None
        }
        resources = await self._fetch_draft_resources(anime, draft, current_time)
        rows: list[dict[str, Any]] = []
        accepted_count = 0
        selected_by_episode: dict[int, tuple[tuple[bool, float], int]] = {}

        for resource in resources:
            match = resource_matches_subscription(resource, rules)
            if not match.matched:
                rows.append(
                    _preview_row(
                        resource,
                        None,
                        ResourceEvaluation(
                            accepted=False,
                            score=0,
                            reason=match.reason,
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
            row = _preview_row(resource, parsed, evaluation, "candidate")
            rows.append(row)
            # Every candidate is a subject match now, so the score decides,
            # mirroring ``_settle_candidates``.
            rank = evaluation.score
            current = selected_by_episode.get(parsed.index)
            if current is None or rank > current[0]:
                selected_by_episode[parsed.index] = (rank, row_index)

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
        # What the editor shows before anything is saved: how much of the season
        # has aired, and which of those episodes these rules actually cover.
        # "Nothing matched" and "nothing aired yet" look identical without it.
        aired = aired_episode_indices(episodes, current_time)
        matched = sorted(selected_by_episode)
        indexed_episodes = [
            episode for episode in episodes if episode.index is not None
        ]
        return {
            "anime_id": anime.id,
            "bangumi_id": anime.bangumi_id,
            "resource_count": len(resources),
            "accepted_count": accepted_count,
            "episode_count": len(indexed_episodes) or int(anime.episode_count or 0),
            "aired_episode_count": len(aired),
            "owned_episode_count": len(existing_indices),
            "matched_episodes": matched,
            "missing_episodes": [
                index
                for index in aired
                if index not in existing_indices and index not in selected_by_episode
            ],
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

            processed = 0
            found = 0
            resource_count = 0
            try:
                for subscription in subscriptions:
                    try:
                        async with session.begin_nested():
                            # One request per show, answering with its whole
                            # history. There is no shared window to draw from any
                            # more: matching is by Bangumi subject id alone, so a
                            # resource the subject query does not return could not
                            # have matched anything anyway.
                            sub_resources = await self._fetch_subject_history(
                                subscription,
                                now,
                            )
                            sub_processed, sub_found = await self._process_subscription(
                                session,
                                subscription,
                                sub_resources,
                                now,
                            )
                        processed += sub_processed
                        found += sub_found
                        resource_count += len(sub_resources)
                        subscription.last_checked_at = now
                        subscription.last_error = None
                        if sub_found:
                            subscription.last_found_at = now
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
                    "resources": resource_count,
                    "found": found,
                    "aborted": True,
                }
            return {
                "subscriptions": len(subscriptions),
                "resources": resource_count,
                "found": found,
                "aborted": False,
            }

    async def _fetch_subject_history(
        self,
        subscription: Subscription,
        now: datetime,
    ) -> list[AnimeGardenResource]:
        """Everything ever published for this show, with no time window at all.

        The window is what loses episodes. Upstream's ``after`` filters on
        publish time, but the index routinely only learns of a release long
        after that: measured against the live feed, ~14% of resources are
        indexed more than an hour late and the tail runs to weeks -- one sampled
        release was published on 12 July and indexed on 20 August. Such a
        release is *born* behind the cursor, so it can never come back, and no
        lookback wide enough to catch it would leave a cursor worth keeping.

        A subject query needs no window: it answers with the show's entire
        history in a single ``complete`` page. Asking for all of it every sweep
        costs one request and cannot miss an episode by windowing.

        Returns nothing when there is no subject to ask by -- such a
        subscription is matched off the shared global window instead.
        """
        queries = await self._queries_for(subscription, subscription.anime)
        if not queries:
            return []
        return await self._fetch_resources(
            after=None,
            before=now,
            queries=queries,
            types=tuple(subscription.resource_types or ("动画",)),
        )

    async def _fetch_draft_resources(
        self,
        anime: Anime,
        draft: Any,
        now: datetime,
    ) -> list[AnimeGardenResource]:
        """What the editor previews: the same unwindowed history as a real check.

        Sharing the fetch is the point. A preview that looked through a
        cold-start window while the worker reads the whole history would promise
        less than the worker goes on to find, which is precisely the drift this
        module exists to avoid.
        """
        return await self._fetch_resources(
            after=None,
            before=now,
            queries=await self._queries_for(draft, anime),
            types=tuple(getattr(draft, "resource_types", None) or ("动画",)),
        )

    async def _queries_for(self, rules_source: Any, anime: Anime | None) -> tuple[_Query, ...]:
        """How this show is asked for upstream: by subject id, and only that.

        The feed's ``subjectId`` *is* the Bangumi id, so one subject query is
        both exact and complete. There is deliberately no query by name, and no
        matching by name either: a name is a guess, and a guess that lands on
        the wrong show files someone else's episode into this library.

        A subject id is therefore all this returns, and nothing without one is
        reachable at all.
        """
        if anime is None:
            return ()
        bangumi_id = int(getattr(anime, "bangumi_id", 0) or 0)
        return (_Query(subjects=(bangumi_id,)),) if bangumi_id else ()

    async def recent_resources(
        self,
        bangumi_id: int,
        *,
        after: datetime,
        before: datetime,
        types: tuple[str, ...] = ("动画",),
    ) -> list[AnimeGardenResource]:
        """Everything published for a subject, for the fansub picker.

        Goes through the same query shaping as a real check, so the groups on
        offer are exactly the groups a subscription would be able to follow.
        The subject id is all that shaping needs -- names never reach the feed.
        """
        return await self._fetch_resources(
            after=after,
            before=before,
            queries=await self._queries_for(
                SimpleNamespace(),
                Anime(id=0, bangumi_id=bangumi_id),
            ),
            types=types,
        )

    async def _fetch_resources(
        self,
        *,
        after: datetime | None,
        before: datetime,
        queries: tuple[_Query, ...] = (),
        types: tuple[str, ...] = ("动画",),
    ) -> list[AnimeGardenResource]:
        """The union of every query, deduped by resource id.

        The same release can come back from more than one query, hence the
        dedupe -- what it prevents is a resource written to the ledger twice,
        since the loop reads the ledger's ids once, before it starts.
        """
        resources: dict[int, AnimeGardenResource] = {}
        for query in queries or (_Query(),):
            await self._walk_pages(
                after=after,
                before=before,
                query=query,
                types=types,
                into=resources,
            )
        return sorted(resources.values(), key=_resource_sort_key)

    async def _walk_pages(
        self,
        *,
        after: datetime | None,
        before: datetime,
        query: _Query = _Query(),
        types: tuple[str, ...] = ("动画",),
        into: dict[int, AnimeGardenResource],
    ) -> None:
        """Page one query to its last page, accumulating into ``into``.

        The walk ends on the feed's own ``complete`` flag or on a page that adds
        nothing new -- and never on a page merely shorter
        than the one requested, because the API silently substitutes its own
        page size when the requested one is out of range. ``max_pages`` is a
        runaway guard, not a window: stopping there is a truncation, so it is
        logged rather than passed off as the end of the feed.
        """
        page_size = _page_size()
        max_pages = _config_int("max_pages", 200)
        walked: set[int] = set()
        for page in range(1, max_pages + 1):
            page_resources, complete = await self.anime_garden.search_resources(
                page=page,
                page_size=page_size,
                after=after,
                before=before,
                subjects=query.subjects,
                search=query.search,
                types=types,
            )
            fresh = sum(1 for resource in page_resources if resource.id not in walked)
            walked.update(resource.id for resource in page_resources)
            into.update({resource.id: resource for resource in page_resources})
            if complete:
                return
            if not fresh:
                # Novelty is measured against this walk's own ids, never the
                # shared accumulator: a page whose every resource an earlier
                # query already contributed is ordinary overlap between queries,
                # and treating it as the end of the feed would abandon this
                # query on its first page. Against ``walked`` the check keeps
                # its real job -- catching a feed that ignores ``page`` and
                # keeps handing back the same window.
                return
        logger.warning(
            "Feed walk hit the %s-page guard (subjects=%s search=%s); "
            "results are truncated",
            max_pages,
            query.subjects,
            query.search,
        )

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
            # Deliberately no cursor comparison here. The ledger already keys on
            # resource id, so re-seeing a resource is a no-op, whereas dropping
            # everything published before the cursor would undo the fetch
            # lookback: a release indexed late is *older* than the cursor by
            # publish time, and is exactly what this pass exists to pick up.
            match = resource_matches_subscription(resource, rules)
            if not match.matched:
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
            immediate = any(
                candidate.score >= profile.accept_now_score for candidate in group
            )
            if not immediate and age_hours < profile.grace_hours:
                continue
            # Every candidate reached the ledger by carrying this show's Bangumi
            # subject id, so there is no weaker kind of evidence to rank against:
            # the score decides, and the earlier arrival breaks a tie.
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


def _resource_sort_key(resource: AnimeGardenResource) -> tuple[datetime, int]:
    return (_naive_utc(resource.created_at) if resource.created_at else datetime.min, resource.id)


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


def _page_size() -> int:
    """How many resources to ask for per page.

    Clamped to what the feed will honour: a larger request is not rejected but
    silently served as a 100-item page, and a page size we cannot trust is the
    thing that made walks stop early in the first place.
    """
    return min(_config_int("page_size", 100), MAX_PAGE_SIZE)


def _config_int(key: str, default: int) -> int:
    try:
        return max(1, int(_subscription_config().get(key, default)))
    except (TypeError, ValueError):
        return default


def _config_bool(key: str, default: bool) -> bool:
    value = _subscription_config().get(key, default)
    return bool(value)


def request_initial_check(subscription_id: int) -> None:
    """Ask the worker loop to check a just-created subscription now.

    Queued for the loop rather than run inline: the sweep lock serialises feed
    access, so a user adding several shows in a row must not fan out into
    parallel sweeps, and the create request must not wait on torrent metadata.
    """
    _pending_initial_checks.add(subscription_id)
    _wakeup.set()


_pending_initial_checks: set[int] = set()
_wakeup = asyncio.Event()


async def _wait_for_work(timeout: float) -> tuple[int, ...]:
    """Sleep until the next sweep is due, or until a new subscription arrives."""
    try:
        await asyncio.wait_for(_wakeup.wait(), timeout=max(0.0, timeout))
    except TimeoutError:
        return ()
    _wakeup.clear()
    pending = tuple(sorted(_pending_initial_checks))
    _pending_initial_checks.clear()
    return pending


def _sweep_interval(*, first_run: bool = False) -> float:
    interval = max(1, _config_int("interval_minutes", 15)) * 60
    spread = min(60, interval if first_run else interval / 10)
    return interval + random.uniform(0, spread)


async def subscription_worker_loop(worker: SubscriptionWorker | None = None) -> None:
    worker = worker or SubscriptionWorker()
    deadline = asyncio.get_running_loop().time() + _sweep_interval(first_run=True)
    while True:
        pending = await _wait_for_work(deadline - asyncio.get_running_loop().time())
        if pending:
            # An early wake-up serves the new subscriptions only; the scheduled
            # sweep keeps its own deadline so adding shows cannot starve it.
            for subscription_id in pending:
                await worker.run_initial_check(subscription_id)
            continue
        deadline = asyncio.get_running_loop().time() + _sweep_interval()
        try:
            result = await worker.run_sweep()
            logger.info("Subscription sweep finished: %s", result)
        except asyncio.CancelledError:
            raise
        except Exception:
            logger.exception("Subscription worker failed")
