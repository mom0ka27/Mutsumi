from __future__ import annotations

import asyncio
from collections import defaultdict
from dataclasses import dataclass
from datetime import UTC, date, datetime, timedelta
import logging
from pathlib import Path
import random
from types import SimpleNamespace
from typing import Any, Callable, Iterable

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
    SubscriptionMatch,
    season_start,
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


# Called after each page with everything gathered so far; ``True`` ends the walk.
_StopCheck = Callable[[dict[int, AnimeGardenResource]], bool]


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
                subscription.backfill_after = None
                if found:
                    subscription.last_found_at = current_time
                if resources:
                    latest = _latest_resource_time(resources)
                    if latest and (subscription.cursor_at is None or latest > subscription.cursor_at):
                        subscription.cursor_at = latest
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
        await self._ensure_aliases(anime)
        rules = subscription_rules(draft, anime)
        values = profile_values(profile, getattr(draft, "profile_overrides", None))
        existing_indices = {
            episode.index for episode in anime.episodes if episode.index is not None
        }
        resources = await self._fetch_draft_resources(
            anime,
            draft,
            current_time,
            episodes,
            stop_when=_coverage_stop(
                rules=rules,
                values=values,
                episodes=episodes,
                owned=existing_indices,
                now=current_time,
            ),
        )
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
            row = _preview_row(resource, parsed, evaluation, "candidate", match=match)
            rows.append(row)
            # Proof before preference: a ``subjectId`` match outranks a
            # title-only one whatever it scores, mirroring ``_settle_candidates``.
            rank = (match.by_subject, evaluation.score)
            current = selected_by_episode.get(parsed.index)
            if current is None or rank > current[0]:
                selected_by_episode[parsed.index] = (rank, row_index)

        for _, row_index in selected_by_episode.values():
            rows[row_index]["selected"] = True
        for row in rows:
            if row["state"] == "candidate" and not row["selected"]:
                row["reason"] = (
                    "同集有 Bangumi subject 命中的候选"
                    if not row["matched_by_subject"]
                    else "同集候选得分更高"
                )
        rows.sort(
            key=lambda row: (
                row["episode_index"] is None,
                row["episode_index"] or 0,
                not row["matched_by_subject"],
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
        await self._walk_pages(
            after=after,
            before=before,
            types=("动画",),
            into=resources,
        )
        return sorted(resources.values(), key=_resource_sort_key)

    async def _fetch_targeted_resources(
        self,
        subscription: Subscription,
        now: datetime,
    ) -> list[AnimeGardenResource]:
        anime = subscription.anime
        # A pending backfill always wins: it is the older window, and the whole
        # point of the first check on a mid-season subscription is to reach past
        # the cold-start days into the episodes already broadcast.
        backfill_after = getattr(subscription, "backfill_after", None)
        if backfill_after is not None:
            after = _naive_utc(backfill_after)
        else:
            after = subscription.cursor_at or now - timedelta(
                days=_config_int("cold_start_days", 7)
            )
        return await self._fetch_resources(
            after=after,
            before=now,
            queries=await self._queries_for(subscription, anime),
            types=tuple(subscription.resource_types or ("动画",)),
            stop_when=await self._coverage_stop_for(subscription, anime, now),
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
            queries=await self._queries_for(subscription, anime),
            types=tuple(subscription.resource_types or ("动画",)),
            stop_when=await self._coverage_stop_for(subscription, anime, now),
        )

    async def _fetch_draft_resources(
        self,
        anime: Anime,
        draft: Any,
        now: datetime,
        episodes: list[Any] = (),
        stop_when: _StopCheck | None = None,
    ) -> list[AnimeGardenResource]:
        return await self._fetch_resources(
            after=_draft_window_start(anime, draft, episodes, now),
            before=now,
            queries=await self._queries_for(draft, anime),
            types=tuple(getattr(draft, "resource_types", None) or ("动画",)),
            stop_when=stop_when,
        )

    async def _coverage_stop_for(
        self,
        subscription: Any,
        anime: Anime | None,
        now: datetime,
    ) -> _StopCheck | None:
        """The early-stop condition for one subscription's own walk.

        Built from Bangumi's episode table, which is cached for the duration of
        a sweep, so asking for it here costs nothing beyond what the check that
        follows would fetch anyway. A Bangumi failure means no early stop rather
        than no check -- the walk just runs to the last page.
        """
        if anime is None or not getattr(anime, "bangumi_id", 0):
            return None
        try:
            episodes = await self.bangumi.get_episodes(anime.bangumi_id)
        except (httpx.HTTPError, ValueError) as error:
            logger.warning(
                "Bangumi episode fetch failed id=%s: %s", anime.bangumi_id, error
            )
            return None
        return _coverage_stop(
            rules=subscription_rules(subscription, anime),
            values=profile_values(
                getattr(subscription, "profile", None),
                getattr(subscription, "profile_overrides", None),
            ),
            episodes=episodes,
            owned={
                episode.index
                for episode in getattr(anime, "episodes", ())
                if episode.index is not None
            },
            now=now,
        )

    async def _queries_for(self, rules_source: Any, anime: Anime | None) -> tuple[_Query, ...]:
        """How this show is asked for upstream: by subject id, or not at all.

        The feed's ``subjectId`` *is* the Bangumi id, so one subject query is
        both exact and complete. There is deliberately no query by name: the
        subject filter already covers everything a name would find, and a name
        query is a guess that costs a request per alias.

        No subject id to ask by -- a subscription that has turned
        ``use_subject_id`` off -- returns no query at all, and the caller then
        pulls the plain window and matches locally, exactly as the global sweep
        does. Names identify the show during matching; they never fetch it.
        """
        if anime is None:
            return ()
        subjects = _subjects_for(anime, getattr(rules_source, "use_subject_id", True))
        return (_Query(subjects=subjects),) if subjects else ()

    async def _ensure_aliases(self, anime: Anime) -> tuple[str, ...]:
        """Bangumi's 别名 list, fetched once and then kept on the row.

        Needed for matching, not for fetching: an untagged resource off the
        global sweep can only be tied to this show by its title, and a release
        titled with an alias is the common case there.

        Filled in lazily rather than by a data migration: rows created before
        the column existed have none, and a subject that gained aliases upstream
        after its row was created would otherwise never pick them up.
        """
        stored = tuple(anime.aliases or ())
        if stored or not anime.bangumi_id:
            return stored
        try:
            subject = await self.bangumi.get_subject(anime.bangumi_id)
        except (httpx.HTTPError, ValueError) as error:
            logger.warning(
                "Bangumi alias fetch failed id=%s: %s", anime.bangumi_id, error
            )
            return ()
        if subject is None or not subject.aliases:
            return ()
        anime.aliases = list(subject.aliases)
        return tuple(subject.aliases)

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
        after: datetime,
        before: datetime,
        queries: tuple[_Query, ...] = (),
        types: tuple[str, ...] = ("动画",),
        stop_when: _StopCheck | None = None,
    ) -> list[AnimeGardenResource]:
        """The union of every query, deduped by resource id.

        One query per name variant is the only way to ask for alternative
        titles: upstream ANDs the terms within a single ``search``. The same
        release commonly comes back from several of them, hence the dedupe.
        """
        resources: dict[int, AnimeGardenResource] = {}
        for query in queries or (_Query(),):
            if stop_when is not None and stop_when(resources):
                break
            await self._walk_pages(
                after=after,
                before=before,
                query=query,
                types=types,
                into=resources,
                stop_when=stop_when,
            )
        return sorted(resources.values(), key=_resource_sort_key)

    async def _walk_pages(
        self,
        *,
        after: datetime,
        before: datetime,
        query: _Query = _Query(),
        types: tuple[str, ...] = ("动画",),
        into: dict[int, AnimeGardenResource],
        stop_when: _StopCheck | None = None,
    ) -> None:
        """Page one query to its last page, accumulating into ``into``.

        The walk ends on the feed's own ``complete`` flag, on a page that adds
        nothing new, or on ``stop_when`` -- and never on a page merely shorter
        than the one requested, because the API silently substitutes its own
        page size when the requested one is out of range. ``max_pages`` is a
        runaway guard, not a window: stopping there is a truncation, so it is
        logged rather than passed off as the end of the feed.
        """
        page_size = _page_size()
        max_pages = _config_int("max_pages", 200)
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
            fresh = sum(1 for resource in page_resources if resource.id not in into)
            into.update({resource.id: resource for resource in page_resources})
            if complete:
                return
            if not fresh:
                # Also the escape hatch for a feed that ignores ``page`` and
                # keeps handing back the same window.
                return
            if stop_when is not None and stop_when(into):
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
        # Aliases are what lets an untagged resource off the global sweep still
        # be recognised by title, so they have to be on the row before matching.
        await self._ensure_aliases(anime)
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
                        match=match,
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
                        match=match,
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
                        match=match,
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
                    match=match,
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
                candidate.score >= profile.accept_now_score
                and _matched_by_subject(candidate)
                for candidate in group
            )
            if not immediate and age_hours < profile.grace_hours:
                continue
            # Proof outranks preference: the indexer's ``subjectId`` is the
            # Bangumi id, so a tagged resource is certainly this show, while a
            # title-only match is a guess two shows can both satisfy. A guess
            # never wins over proof, however well it scores.
            winner = max(
                group,
                key=lambda candidate: (
                    _matched_by_subject(candidate),
                    candidate.score,
                    -_naive_utc(candidate.first_seen_at).timestamp(),
                ),
            )
            for candidate in group:
                if candidate is not winner:
                    candidate.state = "skipped"
                    candidate.reason = (
                        "同集候选得分更高"
                        if _matched_by_subject(candidate) == _matched_by_subject(winner)
                        else "同集有 Bangumi subject 命中的候选"
                    )
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
    match: SubscriptionMatch | None = None,
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
            # Read back by ``_settle_candidates`` to rank proof above preference.
            "matched_by": (match or SubscriptionMatch(True)).matched_by,
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


def _matched_by_subject(candidate: SubscriptionEpisode) -> bool:
    """Whether the ledger row was proven to be this show by its Bangumi id.

    Rows written before the evidence was recorded read as unproven, which only
    means they lose a tie against a tagged resource -- the safe direction.
    """
    return (candidate.attributes or {}).get("matched_by") == MATCHED_BY_SUBJECT


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
    match: SubscriptionMatch | None = None,
) -> dict[str, Any]:
    attributes = dict(evaluation.attributes)
    attributes["episode_parse"] = {
        "raw_number": parsed.raw_number if parsed else None,
        "reason": parsed.reason if parsed else None,
    }
    if match is not None:
        attributes["matched_by"] = match.matched_by
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
        "matched_by_subject": bool(match and match.by_subject),
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


def backfill_window_start(
    air_date: datetime | date | str | None,
    episodes: Iterable[Any] = (),
    now: datetime | None = None,
) -> datetime:
    """The oldest point a whole-season catch-up has to reach.

    Shared by the editor preview and the first real check, so that what the
    preview promised is what the worker then goes and fetches. The extra day
    covers releases that land slightly ahead of the listed broadcast time.
    """
    current = now or _utcnow()
    cold_start = current - timedelta(days=_config_int("cold_start_days", 7))
    start = season_start(air_date, episodes)
    if start is None:
        return cold_start
    return min(cold_start, start - timedelta(days=1))


def _draft_window_start(
    anime: Anime,
    draft: Any,
    episodes: Iterable[Any],
    now: datetime,
) -> datetime:
    """How far back a preview looks.

    With ``backfill_aired`` on it has to span the whole broadcast season: the
    cold-start window would answer "no resources" for exactly the mid-season
    case the switch exists for.
    """
    if not getattr(draft, "backfill_aired", False):
        return now - timedelta(days=_config_int("cold_start_days", 7))
    return backfill_window_start(getattr(anime, "air_date", None), episodes, now)


def _coverage_stop(
    *,
    rules: Any,
    values: ProfileValues,
    episodes: list[Any],
    owned: Iterable[int],
    now: datetime,
) -> _StopCheck | None:
    """Stop paging once every aired episode still missing has a usable release.

    Sound only because the feed is strictly newest-first: once the oldest thing
    we lack has been found, older pages cannot hold anything else we need. It
    asks for an *accepted* release, not merely a resource carrying that episode
    number, so a walk never ends on candidates the rules would throw away.

    Returns ``None`` -- no early stop, walk to the last page -- when there is
    nothing known to be missing. That is what keeps a release for an episode
    Bangumi has not published or dated yet reachable.
    """
    held = set(owned)
    needed = frozenset(
        index for index in aired_episode_indices(episodes, now) if index not in held
    )
    if not needed:
        return None
    anime_name = str(getattr(rules, "anime_name", "") or "")
    offset = getattr(rules, "episode_offset_override", None)
    covered: set[int] = set()
    judged: set[int] = set()

    def reached(resources: dict[int, AnimeGardenResource]) -> bool:
        for resource_id, resource in resources.items():
            if resource_id in judged:
                continue
            judged.add(resource_id)
            if not resource_matches_subscription(resource, rules).matched:
                continue
            if not evaluate_resource(resource, values, rules).accepted:
                continue
            parsed = parse_episode_index(
                resource.title,
                episodes,
                resource.created_at,
                episode_offset_override=offset,
                anime_name=anime_name,
            )
            if parsed.index is not None:
                covered.add(parsed.index)
        return needed <= covered

    return reached


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
