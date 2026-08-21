from __future__ import annotations

import asyncio
from dataclasses import dataclass, field
import time
from typing import Any

import httpx

from app.services.subscription_engine import EpisodeInfo


BANGUMI_BASE_URL = "https://api.bgm.tv"

# ``type=0`` keeps the response to main-story episodes. Specials must stay out:
# a late BD extra would otherwise push max(airdate) into the future forever and
# leave a finished show looking like it is still airing.
MAIN_EPISODE_TYPE = 0


@dataclass(frozen=True)
class SubjectInfo:
    """The subset of a Bangumi subject needed to create an ``Anime`` row."""

    bangumi_id: int
    name: str = ""
    name_cn: str = ""
    summary: str = ""
    image_url: str = ""
    score: float = 0
    episode_count: int = 0
    air_date: str = ""
    rank: int = 0
    platform: str = ""
    tags: list[str] = field(default_factory=list)
    infobox: list[dict[str, str]] = field(default_factory=list)


class BangumiService:
    def __init__(
        self,
        client: httpx.AsyncClient | None = None,
        base_url: str = BANGUMI_BASE_URL,
        cache_seconds: float = 600,
    ) -> None:
        self._client = client
        self._base_url = base_url.rstrip("/")
        self._cache_seconds = cache_seconds
        self._cache: dict[int, tuple[float, list[EpisodeInfo]]] = {}
        self._subject_cache: dict[int, tuple[float, SubjectInfo | None]] = {}
        self._lock = asyncio.Lock()

    async def get_episodes(self, subject_id: int) -> list[EpisodeInfo]:
        now = time.monotonic()
        cached = self._cache.get(subject_id)
        if cached and now - cached[0] < self._cache_seconds:
            return list(cached[1])

        async with self._lock:
            now = time.monotonic()
            cached = self._cache.get(subject_id)
            if cached and now - cached[0] < self._cache_seconds:
                return list(cached[1])
            episodes = await self._fetch_episodes(subject_id)
            self._cache[subject_id] = (time.monotonic(), episodes)
            return list(episodes)

    async def get_subject(self, subject_id: int) -> SubjectInfo | None:
        """Subject metadata, cached alongside the episode list.

        Returns ``None`` when the subject does not exist upstream, which is a
        normal answer rather than an error: the caller decides whether a
        subscription without metadata is still worth creating.
        """
        now = time.monotonic()
        cached = self._subject_cache.get(subject_id)
        if cached and now - cached[0] < self._cache_seconds:
            return cached[1]

        async with self._lock:
            now = time.monotonic()
            cached = self._subject_cache.get(subject_id)
            if cached and now - cached[0] < self._cache_seconds:
                return cached[1]
            subject = await self._fetch_subject(subject_id)
            self._subject_cache[subject_id] = (time.monotonic(), subject)
            return subject

    async def _fetch_subject(self, subject_id: int) -> SubjectInfo | None:
        payload = await self._get_json(f"/v0/subjects/{subject_id}")
        if not isinstance(payload, dict) or not payload.get("id"):
            return None
        return _subject_from_json(payload)

    async def _fetch_episodes(self, subject_id: int) -> list[EpisodeInfo]:
        limit = 100
        offset = 0
        episodes: list[EpisodeInfo] = []
        while offset < 2000:
            params = {
                "subject_id": subject_id,
                "type": MAIN_EPISODE_TYPE,
                "limit": limit,
                "offset": offset,
            }
            payload = await self._get_json("/v0/episodes", params=params)
            if not isinstance(payload, dict):
                break
            data = payload.get("data")
            if not isinstance(data, list):
                break
            for item in data:
                if not isinstance(item, dict):
                    continue
                episode = _episode_from_json(item)
                if episode is not None:
                    episodes.append(episode)
            if len(data) < limit:
                break
            total = _number(payload.get("total"))
            offset += len(data)
            if total is not None and offset >= total:
                break
        return episodes

    async def _get_json(
        self,
        path: str,
        params: dict[str, Any] | None = None,
    ) -> Any:
        if self._client is not None:
            response = await self._client.get(path, params=params)
            response.raise_for_status()
            return response.json()
        async with httpx.AsyncClient(base_url=self._base_url, timeout=30) as client:
            response = await client.get(path, params=params)
            response.raise_for_status()
            return response.json()


def _episode_from_json(item: dict[str, Any]) -> EpisodeInfo | None:
    ep = _number(item.get("ep"))
    sort = _number(item.get("sort"))
    if ep is None or sort is None:
        return None
    return EpisodeInfo(
        ep=ep,
        sort=sort,
        name=str(item.get("name") or ""),
        name_cn=str(item.get("name_cn") or ""),
        airdate=item.get("airdate") or item.get("air_date"),
    )


def _subject_from_json(item: dict[str, Any]) -> SubjectInfo:
    images = item.get("images")
    rating = item.get("rating")
    return SubjectInfo(
        bangumi_id=int(item.get("id") or 0),
        name=str(item.get("name") or ""),
        name_cn=str(item.get("name_cn") or ""),
        summary=str(item.get("summary") or ""),
        image_url=_image_url(images),
        score=float(_number(_nested(rating, "score")) or 0),
        # ``eps`` counts main-story episodes; ``total_episodes`` also counts
        # specials, so it would misreport the season length.
        episode_count=int(_number(item.get("eps")) or 0),
        air_date=str(item.get("date") or ""),
        rank=int(_number(_nested(rating, "rank")) or 0),
        platform=str(item.get("platform") or ""),
        tags=[
            str(tag.get("name"))
            for tag in item.get("tags") or []
            if isinstance(tag, dict) and tag.get("name")
        ],
        infobox=[
            {"key": str(entry.get("key")), "value": str(entry.get("value"))}
            # Multi-value keys (别名, 主题歌) arrive as lists; the Anime model
            # stores flat key/value pairs, so those entries are dropped rather
            # than stringified into noise.
            for entry in item.get("infobox") or []
            if isinstance(entry, dict)
            and entry.get("key")
            and isinstance(entry.get("value"), str)
        ],
    )


def _image_url(images: Any) -> str:
    if not isinstance(images, dict):
        return ""
    for key in ("large", "common", "medium", "small", "grid"):
        value = images.get(key)
        if isinstance(value, str) and value:
            return value
    return ""


def _nested(value: Any, key: str) -> Any:
    return value.get(key) if isinstance(value, dict) else None


def _number(value: Any) -> float | None:
    try:
        number = float(value)
    except (TypeError, ValueError):
        return None
    return number if number == number else None
