from __future__ import annotations

import asyncio
from dataclasses import dataclass
import time
from typing import Any

import httpx

from app.services.subscription_engine import EpisodeInfo


BANGUMI_BASE_URL = "https://api.bgm.tv"


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

    async def _fetch_episodes(self, subject_id: int) -> list[EpisodeInfo]:
        limit = 100
        offset = 0
        episodes: list[EpisodeInfo] = []
        while offset < 2000:
            params = {"subject_id": subject_id, "limit": limit, "offset": offset}
            if self._client is not None:
                response = await self._client.get("/v0/episodes", params=params)
                response.raise_for_status()
                payload = response.json()
            else:
                async with httpx.AsyncClient(base_url=self._base_url, timeout=30) as client:
                    response = await client.get("/v0/episodes", params=params)
                    response.raise_for_status()
                    payload = response.json()
            if not isinstance(payload, dict):
                break
            data = payload.get("data")
            if not isinstance(data, list):
                break
            episodes.extend(
                _episode_from_json(item)
                for item in data
                if isinstance(item, dict) and _episode_from_json(item) is not None
            )
            if len(data) < limit:
                break
            total = _number(payload.get("total"))
            offset += len(data)
            if total is not None and offset >= total:
                break
        return episodes


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


def _number(value: Any) -> float | None:
    try:
        number = float(value)
    except (TypeError, ValueError):
        return None
    return number if number == number else None
