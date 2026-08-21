from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from typing import Any, Iterable

import httpx


ANIME_GARDEN_BASE_URL = "https://api.animes.garden"

# Out-of-range page sizes are not rejected, they are silently replaced: asking
# for 2000 comes back as ``pagination.pageSize: 100`` with 100 items. 1000 is
# the largest size observed to be honoured, so requests are clamped to it --
# past that the feed would quietly serve a tenth of what was asked for.
MAX_PAGE_SIZE = 1000


@dataclass(frozen=True)
class AnimeGardenResource:
    id: int
    provider: str
    provider_id: str
    title: str
    type: str
    magnet: str
    tracker: str
    size: int
    fansub_name: str
    publisher_name: str
    created_at: datetime | None
    subject_ids: frozenset[int] = frozenset()

    @property
    def download_link(self) -> str:
        return f"{self.magnet}{self.tracker}" if self.tracker else self.magnet


class AnimeGardenService:
    def __init__(
        self,
        client: httpx.AsyncClient | None = None,
        base_url: str = ANIME_GARDEN_BASE_URL,
    ) -> None:
        self._client = client
        self._base_url = base_url.rstrip("/")

    async def search_resources(
        self,
        *,
        page: int = 1,
        page_size: int = 100,
        after: datetime | None = None,
        before: datetime | None = None,
        subjects: Iterable[int] = (),
        fansubs: Iterable[str] = (),
        search: Iterable[str] = (),
        include: Iterable[str] = (),
        keywords: Iterable[str] = (),
        exclude: Iterable[str] = (),
        types: Iterable[str] = ("动画",),
    ) -> tuple[list[AnimeGardenResource], bool]:
        """One page of the feed, plus whether it is the last one.

        ``complete`` is deliberately conservative: the caller pages until it is
        set, so a wrong ``True`` silently drops resources -- which is what the
        old "fewer items than requested" test did whenever the feed ignored the
        requested page size.
        """
        requested_size = max(1, min(int(page_size), MAX_PAGE_SIZE))
        query = {"page": page, "pageSize": requested_size, "tracker": True}
        body: dict[str, Any] = {}
        self._add_list(body, "subjects", subjects)
        self._add_list(body, "fansubs", fansubs)
        self._add_list(body, "search", search)
        self._add_list(body, "include", include)
        self._add_list(body, "keywords", keywords)
        self._add_list(body, "exclude", exclude)
        self._add_list(body, "types", types)
        if after is not None:
            body["after"] = _isoformat(after)
        if before is not None:
            body["before"] = _isoformat(before)

        if self._client is not None:
            response = await self._client.post("/resources", params=query, json=body)
            response.raise_for_status()
            payload = response.json()
        else:
            async with httpx.AsyncClient(base_url=self._base_url, timeout=30) as client:
                response = await client.post("/resources", params=query, json=body)
                response.raise_for_status()
                payload = response.json()

        if not isinstance(payload, dict):
            return [], True
        raw_resources = payload.get("resources") or payload.get("data") or payload.get("items")
        if not isinstance(raw_resources, list):
            return [], True
        resources = [
            resource
            for item in raw_resources
            if isinstance(item, dict)
            for resource in [_resource_from_json(item)]
            if resource.id > 0 and resource.title
        ]
        pagination = payload.get("pagination")
        complete = bool(payload.get("complete"))
        if isinstance(pagination, dict):
            complete = complete or bool(pagination.get("complete"))
        if complete:
            return resources, True
        if not raw_resources:
            return resources, True  # Nothing on this page: past the end.
        # A short page ends the walk only when measured against the size the
        # server says it applied -- never the size that was asked for. Counting
        # raw items rather than parsed ones matters too: one malformed entry on
        # a full page must not read as "the last page".
        effective_size = _int_or_none(
            pagination.get("pageSize") if isinstance(pagination, dict) else None
        )
        if effective_size and len(raw_resources) < effective_size:
            return resources, True
        return resources, False

    @staticmethod
    def _add_list(target: dict[str, Any], key: str, values: Iterable[Any]) -> None:
        normalized = [value for value in values if value not in (None, "")]
        if normalized:
            target[key] = normalized


def _isoformat(value: datetime) -> str:
    return value.isoformat().replace("+00:00", "Z")


def _resource_from_json(item: dict[str, Any]) -> AnimeGardenResource:
    fansub = item.get("fansub")
    publisher = item.get("publisher")
    return AnimeGardenResource(
        id=_int_value(item.get("id")),
        provider=str(item.get("provider") or ""),
        provider_id=str(item.get("providerId") or item.get("provider_id") or ""),
        title=str(item.get("title") or ""),
        type=str(item.get("type") or ""),
        magnet=str(item.get("magnet") or ""),
        tracker=str(item.get("tracker") or ""),
        size=_int_value(item.get("size")),
        fansub_name=_nested_name(fansub),
        publisher_name=_nested_name(publisher),
        created_at=_datetime_value(item.get("createdAt") or item.get("created_at")),
        subject_ids=frozenset(_subject_ids(item)),
    )


def _nested_name(value: Any) -> str:
    if isinstance(value, dict):
        return str(value.get("name") or value.get("title") or "")
    return str(value or "")


def _int_or_none(value: Any) -> int | None:
    """A positive int, or nothing -- used where zero must not act as a limit."""
    try:
        number = int(value)
    except (TypeError, ValueError):
        return None
    return number if number > 0 else None


def _int_value(value: Any) -> int:
    try:
        return int(value or 0)
    except (TypeError, ValueError):
        return 0


def _datetime_value(value: Any) -> datetime | None:
    if not value:
        return None
    try:
        return datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    except ValueError:
        return None


def _subject_ids(item: dict[str, Any]) -> set[int]:
    result: set[int] = set()

    def add(value: Any) -> None:
        if isinstance(value, dict):
            for key in ("id", "subjectId", "subject_id", "bangumiId", "bangumi_id"):
                if key in value:
                    add(value[key])
        elif isinstance(value, list):
            for item_value in value:
                add(item_value)
        else:
            try:
                number = int(value)
            except (TypeError, ValueError):
                return
            if number > 0:
                result.add(number)

    for key in ("subjectId", "subject_id", "bangumiId", "bangumi_id", "subject", "subjects"):
        if key in item:
            add(item[key])
    return result
