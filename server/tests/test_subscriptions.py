from datetime import datetime
from types import SimpleNamespace

import httpx
import pytest

from app.models import PermissionGroup
from app.models import Anime, Episode, PreferenceProfile, Subscription
from app.schemas.qbittorrent import QBittorrentFileRead, QBittorrentTorrentAddResult
from app.services.animegarden_service import (
    MAX_PAGE_SIZE,
    AnimeGardenResource,
    AnimeGardenService,
)
from app.api.routes import subscriptions as routes_subscriptions
from app.services.bangumi_service import SubjectInfo, _subject_from_json
from app.services.subscription_engine import (
    EpisodeInfo,
    _extract_episode_number,
    aired_episode_indices,
    derive_airing_status,
    evaluate_resource,
    parse_episode_index,
    parse_title_attributes,
    profile_values,
    resource_matches_subscription,
    subtitle_tokens,
    SubscriptionRules,
)
from app.services import subscription_worker as worker_module
from app.services.subscription_worker import SubscriptionWorker


class Resource:
    def __init__(self, title, fansub_name="ANi", resource_type="动画"):
        self.id = 1
        self.title = title
        self.fansub_name = fansub_name
        self.type = resource_type
        self.subject_ids = frozenset({4242})


class FakeBangumi:
    """Bangumi with nothing to say, unless a test hands it something."""

    def __init__(self, episodes=(), subject=None):
        self._episodes = list(episodes)
        self._subject = subject

    async def get_episodes(self, subject_id):
        return list(self._episodes)

    async def get_subject(self, subject_id):
        return self._subject


def _feed_resource(resource_id: int, title: str, fansub: str = "ANi"):
    return AnimeGardenResource(
        id=resource_id,
        provider="test",
        provider_id=str(resource_id),
        title=title,
        type="动画",
        magnet=f"magnet:?xt=urn:btih:{resource_id}",
        tracker="",
        size=100,
        fansub_name=fansub,
        publisher_name="",
        created_at=datetime.fromisoformat("2026-08-20T10:00:00"),
        subject_ids=frozenset({4242}),
    )


_PREVIEW_PROFILE = PreferenceProfile(
    name="默认",
    is_default=True,
    language_mode="简",
    language_unknown="accept",
    prefer_resolution=["1080p", "720p"],
    prefer_codec=["avc"],
    prefer_subtitle=["简", "繁", "日", "无"],
    prefer_bitdepth=["10bit", "8bit"],
    weights={"fansub": 45, "resolution": 22, "codec": 15, "subtitle": 12, "bitdepth": 6},
)

_PREVIEW_DRAFT = SimpleNamespace(
    fansub="ANi",
    allow_no_fansub=False,
    search_keywords=[],
    must_include=[],
    exclude_keywords=[],
    use_subject_id=True,
    resource_types=["动画"],
    profile_overrides=None,
    episode_offset_override=None,
)


def test_title_attributes_handle_underscore_codec_and_language_fallback():
    attributes = parse_title_attributes("[ANi] 作品 01 [简日][AV1_opus][1080p]")

    assert attributes["language"]["script"] == ["简"]
    assert attributes["language"]["has_jp"] is True
    assert attributes["codec"] == "av1"
    assert attributes["resolution"] == "1080p"


def test_cantonese_is_rejected_even_when_unknown_titles_are_accepted():
    profile = profile_values(None)
    result = evaluate_resource(
        Resource("[ANi] 作品 01 [粤语][1080p]"),
        profile,
        SubscriptionRules(bangumi_id=4242, fansub="ANi"),
    )

    assert result.accepted is False
    assert result.reason == "字幕语言被明确排除"


def test_episode_parser_maps_absolute_sort_number_to_season_index():
    episodes = [
        EpisodeInfo(ep=1, sort=12, name_cn="第一集", airdate="2024-07-03"),
        EpisodeInfo(ep=2, sort=13, name_cn="第二集", airdate="2024-07-10"),
    ]

    result = parse_episode_index(
        "[Group] 作品 - 13 [1080p]",
        episodes,
        datetime.fromisoformat("2024-07-12T00:00:00"),
    )

    assert result.index == 2


def test_episode_parser_rejects_future_airdate():
    result = parse_episode_index(
        "[Group] 作品 - 01",
        [EpisodeInfo(ep=1, sort=1, airdate="2026-08-21")],
        datetime.fromisoformat("2026-08-20T12:00:00"),
    )

    assert result.index is None
    assert result.reason == "对应集数尚未播出，拦截疑似误解析"


@pytest.mark.parametrize(
    ("title", "expected"),
    [
        # 8 and 10 collide with 8bit/10bit, so a value blocklist would make
        # every season's episodes 8 and 10 unparseable.
        ("[G] 作品 - 08 [1080p]", 8),
        ("[G] 作品 [08][1080p][繁體]", 8),
        ("[G] 作品 第08话 [1080p]", 8),
        ("[G] 作品 - 10 [1080p][10bit]", 10),
        ("[G] 作品 [10][WebRip 1920x1080 x264 10bit AAC 2.0]", 10),
        ("[G] 作品 第10集 [1080p]", 10),
        ("[G] 作品 - 12 END [2160p][HEVC-10bit][FLAC]", 12),
    ],
)
def test_episode_parser_sees_through_technical_tokens(title, expected):
    episodes = [
        EpisodeInfo(ep=index, sort=index, airdate="2026-08-01")
        for index in range(1, 13)
    ]

    result = parse_episode_index(
        title,
        episodes,
        datetime.fromisoformat("2026-08-20T00:00:00"),
    )

    assert result.index == expected


@pytest.mark.parametrize(
    "title",
    [
        "[ANi] 作品 Season 4 - 03 [1080P][Baha][WEB-DL][AAC AVC][CHT]",
        "[喵萌奶茶屋] 作品 S2 - 03 [1080p][简繁日内封]",
        "[Nekomoe kissaten] 作品 - 03 [x264-10bit AAC][简日]",
    ],
)
def test_spaced_separator_is_not_an_episode_range(title):
    result = parse_episode_index(
        title,
        [EpisodeInfo(ep=3, sort=3, airdate="2026-08-01")],
        datetime.fromisoformat("2026-08-20T00:00:00"),
    )

    assert result.index == 3, result.reason


@pytest.mark.parametrize(
    "title",
    [
        "[SweetSub] 作品 [01-12][BDRip][1080p]",
        "[G] 作品 第01-12话 [1080p]",
        "[G] 作品 01~24 [1080p]",
    ],
)
def test_real_episode_ranges_are_still_filtered(title):
    result = evaluate_resource(
        Resource(title),
        profile_values(None),
        SubscriptionRules(bangumi_id=4242, fansub="ANi"),
    )

    assert result.accepted is False
    assert result.reason in {"集数区间资源", "合集或批量资源"}


def test_fansub_dimension_is_neutral_when_nothing_was_selected():
    profile = profile_values(None)

    result = evaluate_resource(
        Resource("[ANi] 作品 - 01 [简][1080p][AVC]"),
        profile,
        SubscriptionRules(bangumi_id=4242, fansub="", allow_no_fansub=True),
    )

    assert result.accepted is True
    # Zero here would cap the total at 0.55 and make accept_now unreachable.
    assert result.component_scores["fansub"] == profile.neutral_score
    assert result.score > profile.neutral_score


def test_a_locked_group_rejects_every_other_group():
    rules = SubscriptionRules(bangumi_id=4242, fansub="喵萌奶茶屋")
    profile = profile_values(None)

    assert evaluate_resource(
        Resource("[喵萌奶茶屋] 作品 - 01 [简日][1080p]", fansub_name="喵萌奶茶屋"),
        profile,
        rules,
    ).accepted is True
    rejected = evaluate_resource(
        Resource("[ANi] 作品 - 01 [简日][2160p]", fansub_name="ANi"),
        profile,
        rules,
    )
    # Better on every other dimension and still out: the lock is the point.
    assert rejected.accepted is False
    assert rejected.reason == "字幕组不是锁定的 喵萌奶茶屋"


def test_a_locked_group_still_gets_its_untagged_releases_when_allowed():
    rules = SubscriptionRules(bangumi_id=4242, fansub="ANi", allow_no_fansub=True)

    assert evaluate_resource(
        Resource("作品 - 01 [简日][1080p]", fansub_name=""),
        profile_values(None),
        rules,
    ).accepted is True


@pytest.mark.parametrize(
    ("title", "expected"),
    [
        # CHS/CHT count as subtitle types, so the group's 简 release outranks its
        # 繁 one instead of both scoring the same.
        ("[G] 作品 - 01 [CHS][1080p]", ("简", "无")),
        ("[G] 作品 - 01 [CHT][1080p]", ("繁", "无")),
        ("[G] 作品 - 01 [简日][1080p]", ("简", "日")),
        ("[G] 作品 - 01 [简繁日内封][1080p]", ("简", "繁", "简繁", "日")),
        ("[G] 作品 - 01 [1080p]", ("无",)),
    ],
)
def test_subtitle_types_include_chs_and_cht(title, expected):
    assert subtitle_tokens(parse_title_attributes(title)["language"]) == expected


def test_the_preferred_script_outranks_the_accepted_one():
    # ``any`` accepts both scripts; the ordering is what expresses "简 preferred,
    # 繁 acceptable" -- a distinction the hard language filter cannot make.
    profile = profile_values(
        None,
        {"language_mode": "any", "prefer_subtitle": ["简", "繁", "日", "无"]},
    )
    rules = SubscriptionRules(bangumi_id=4242, fansub="ANi")

    simplified = evaluate_resource(
        Resource("[ANi] 作品 - 01 [CHS][1080p][AVC]"), profile, rules
    )
    traditional = evaluate_resource(
        Resource("[ANi] 作品 - 01 [CHT][1080p][AVC]"), profile, rules
    )

    assert simplified.accepted and traditional.accepted
    assert simplified.component_scores["subtitle"] == 1
    assert traditional.component_scores["subtitle"] == 0.75
    assert simplified.score > traditional.score


async def test_subscribing_without_a_lock_is_rejected(client, auth_headers):
    user_headers = await auth_headers(PermissionGroup.USER)

    response = client.post(
        "/api/v1/subscriptions",
        json={"bangumi_id": 4242},
        headers=user_headers,
    )

    assert response.status_code == 422
    assert "锁定" in response.json()["detail"]


async def test_targeted_check_does_not_and_the_anime_name_with_the_subject_id():
    calls: list[dict] = []

    class FakeAnimeGarden:
        async def search_resources(self, **kwargs):
            calls.append(kwargs)
            return [], True

    subscription = SimpleNamespace(
        anime=Anime(id=1, bangumi_id=4242, name="Long Original Name", name_cn="作品"),
        cursor_at=None,
        search_keywords=[],
        use_subject_id=True,
        resource_types=["动画"],
    )

    await SubscriptionWorker(
        anime_garden=FakeAnimeGarden(),
        bangumi=FakeBangumi(),
    )._fetch_subject_history(
        subscription,
        datetime.fromisoformat("2026-08-20T12:00:00"),
    )

    assert calls
    assert calls[0]["subjects"] == (4242,)
    assert calls[0]["search"] == ()


async def test_delivery_waits_for_metadata_and_creates_the_episode(monkeypatch):
    metadata_calls: list[str] = []

    async def fake_metadata(source: str):
        metadata_calls.append(source)
        return [
            QBittorrentFileRead(name="作品 - 01.mkv", size=800 * 1024 * 1024, id=0),
            QBittorrentFileRead(name="作品 - 01.ass", size=40 * 1024, id=1),
        ]

    async def fake_download(payload, _user):
        return QBittorrentTorrentAddResult(hash="a" * 40)

    monkeypatch.setattr(worker_module, "fetch_torrent_metadata_files", fake_metadata)
    monkeypatch.setattr(worker_module, "download_torrent_files", fake_download)

    class FakeSession:
        def __init__(self):
            self.added = []

        async def scalar(self, *_args, **_kwargs):
            return None

        def add(self, item):
            self.added.append(item)

    session = FakeSession()
    subscription = Subscription(
        id=1,
        anime=Anime(id=7, bangumi_id=4242, name="Test Anime", name_cn="测试"),
    )
    candidate = worker_module.SubscriptionEpisode(
        subscription_id=1,
        episode_index=1,
        resource_id=99,
        resource_title="[ANi] 作品 - 01 [1080p]",
        score=0.9,
        attributes={
            "download_link": "magnet:?xt=urn:btih:test",
            "episode_parse": {"name_cn": "第一集"},
        },
        state="candidate",
    )

    await SubscriptionWorker()._deliver_candidate(
        session,
        subscription,
        candidate,
        set(),
    )

    assert metadata_calls == ["magnet:?xt=urn:btih:test"]
    assert candidate.state == "imported"
    assert candidate.download_hash == "a" * 40
    episodes = [item for item in session.added if isinstance(item, Episode)]
    assert len(episodes) == 1
    assert (episodes[0].index, episodes[0].name) == (1, "第一集")
    assert episodes[0].filename == "作品 - 01.mkv"


async def test_subscription_crud_and_guest_permission(client, auth_headers):
    user_headers = await auth_headers(PermissionGroup.USER)
    anime = client.post(
        "/api/v1/anime",
        json={"bangumi_id": 4242, "name": "Test Anime", "name_cn": "测试"},
        headers=user_headers,
    )
    assert anime.status_code == 201, anime.text
    anime_id = anime.json()["id"]

    profiles = client.get("/api/v1/preference-profiles", headers=user_headers)
    assert profiles.status_code == 200, profiles.text
    profile_id = profiles.json()[0]["id"]

    created = client.post(
        "/api/v1/subscriptions",
        json={
            "bangumi_id": 4242,
            "profile_id": profile_id,
            "fansub": "ANi",
        },
        headers=user_headers,
    )
    assert created.status_code == 201, created.text
    assert created.json()["anime_name_cn"] == "测试"
    assert created.json()["anime_id"] == anime_id

    listed = client.get("/api/v1/subscriptions", headers=user_headers)
    assert listed.status_code == 200
    assert len(listed.json()) == 1

    guest_headers = await auth_headers(PermissionGroup.GUEST)
    forbidden = client.post(
        "/api/v1/subscriptions",
        json={"bangumi_id": 4242},
        headers=guest_headers,
    )
    assert forbidden.status_code == 403

    # ``/preview`` belongs to the write side: it is part of the configuration
    # flow and hits the upstream feed on the user's behalf.
    guest_preview = client.post(
        "/api/v1/subscriptions/preview",
        json={"bangumi_id": 4242},
        headers=guest_headers,
    )
    assert guest_preview.status_code == 403
    assert (
        client.get(
            "/api/v1/preference-profiles",
            headers=guest_headers,
        ).status_code
        == 200
    )


async def test_preview_picks_the_best_release_of_the_locked_group_only():
    def resource(resource_id: int, title: str, fansub: str) -> AnimeGardenResource:
        return AnimeGardenResource(
            id=resource_id,
            provider="test",
            provider_id=str(resource_id),
            title=title,
            type="动画",
            magnet=f"magnet:?xt=urn:btih:{resource_id}",
            tracker="",
            size=100,
            fansub_name=fansub,
            publisher_name="",
            created_at=datetime.fromisoformat("2026-08-20T10:00:00"),
            subject_ids=frozenset({4242}),
        )

    class FakeAnimeGarden:
        async def search_resources(self, **kwargs):
            return [
                resource(1, "[ANi] Test Anime - 01 [简][1080p][avc]", "ANi"),
                # Same group, worse resolution: this is the comparison a locked
                # subscription actually makes.
                resource(2, "[ANi] Test Anime - 01 [简][720p][avc]", "ANi"),
                # A different group is out of the running entirely, however good.
                resource(3, "[Other] Test Anime - 01 [简][2160p][avc]", "Other"),
            ], True

    class FakeBangumi:
        async def get_episodes(self, subject_id):
            return [EpisodeInfo(ep=1, sort=1, name_cn="第一集", airdate="2026-08-19")]

        async def get_subject(self, subject_id):
            return None

    anime = Anime(id=1, bangumi_id=4242, name="Test Anime", name_cn="测试")
    profile = PreferenceProfile(
        name="默认",
        is_default=True,
        language_mode="简",
        language_unknown="accept",
        prefer_resolution=["1080p", "720p"],
        prefer_codec=["avc"],
        prefer_subtitle=["日", "无"],
        prefer_bitdepth=["10bit", "8bit"],
        weights={"fansub": 45, "resolution": 22, "codec": 15, "subtitle": 12, "bitdepth": 6},
    )
    draft = SimpleNamespace(
        fansub="ANi",
        allow_no_fansub=False,
        search_keywords=[],
        must_include=[],
        exclude_keywords=[],
        use_subject_id=True,
        resource_types=["动画"],
        profile_overrides=None,
        episode_offset_override=None,
    )

    result = await SubscriptionWorker(
        anime_garden=FakeAnimeGarden(),
        bangumi=FakeBangumi(),
    ).preview(
        anime=anime,
        profile=profile,
        draft=draft,
        now=datetime.fromisoformat("2026-08-20T12:00:00"),
    )

    selected = [item for item in result["candidates"] if item["selected"]]
    assert result["accepted_count"] == 2
    assert len(selected) == 1
    assert selected[0]["resource_id"] == 1
    rejected = next(
        item for item in result["candidates"] if item["resource_id"] == 3
    )
    assert rejected["reason"] == "字幕组不是锁定的 ANi"


def _raw_item(resource_id: int) -> dict:
    return {
        "id": resource_id,
        "title": f"[ANi] Test Anime - {resource_id:02d} [简][1080p][avc]",
        "type": "动画",
        "magnet": f"magnet:?xt=urn:btih:{resource_id}",
        "createdAt": "2026-08-20T10:00:00Z",
    }


async def _one_page(payload: dict, **kwargs):
    requests: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        requests.append(request)
        return httpx.Response(200, json=payload)

    async with httpx.AsyncClient(
        transport=httpx.MockTransport(handler),
        base_url="https://feed.test",
    ) as client:
        result = await AnimeGardenService(client=client).search_resources(**kwargs)
    return result, requests


async def test_a_page_size_the_feed_replaced_with_its_own_cannot_end_the_walk():
    # Out-of-range sizes are not rejected upstream, they are substituted: the
    # reply carries pageSize 100 with 100 items. Measuring against the size that
    # was *asked for* would call that the last page and drop the rest of the feed.
    (resources, complete), requests = await _one_page(
        {
            "resources": [_raw_item(index) for index in range(1, 101)],
            "pagination": {"page": 1, "pageSize": 100, "complete": False},
        },
        page=1,
        page_size=2000,
    )

    assert len(resources) == 100
    assert complete is False
    # And the request itself never asks for more than the feed will honour.
    assert requests[0].url.params["pageSize"] == str(MAX_PAGE_SIZE)


async def test_one_unparsable_entry_does_not_shorten_a_full_page():
    (resources, complete), _ = await _one_page(
        {
            "resources": [
                *[_raw_item(index) for index in range(1, 100)],
                {"id": 0, "title": ""},
            ],
            "pagination": {"page": 1, "pageSize": 100, "complete": False},
        },
        page=1,
        page_size=100,
    )

    assert len(resources) == 99
    assert complete is False


async def test_a_page_short_of_the_applied_size_is_the_last_page():
    (resources, complete), _ = await _one_page(
        {
            "resources": [_raw_item(index) for index in range(1, 96)],
            "pagination": {"page": 1, "pageSize": 100, "complete": False},
        },
        page=1,
        page_size=100,
    )

    assert len(resources) == 95
    assert complete is True


async def test_an_empty_page_is_the_last_page():
    (resources, complete), _ = await _one_page(
        {
            "resources": [],
            "pagination": {"page": 2, "pageSize": 100, "complete": False},
        },
        page=2,
        page_size=100,
    )

    assert resources == []
    assert complete is True


def _subject_subscription() -> SimpleNamespace:
    """The minimum a fetch needs: a show with a Bangumi id to ask by."""
    return SimpleNamespace(
        anime=Anime(id=1, bangumi_id=4242, name="Test Anime", name_cn="测试"),
        search_keywords=[],
        resource_types=["动画"],
    )


async def test_the_walk_runs_to_the_last_page_not_to_a_page_ceiling():
    seen: list[int] = []

    class FakeAnimeGarden:
        async def search_resources(self, *, page, **kwargs):
            seen.append(page)
            if page > 7:
                return [], True
            return [_feed_resource(page, f"[ANi] Test Anime - {page:02d} [简][1080p]")], False

    resources = await SubscriptionWorker(
        anime_garden=FakeAnimeGarden(),
        bangumi=FakeBangumi(),
    )._fetch_subject_history(
        _subject_subscription(),
        datetime.fromisoformat("2026-08-20T12:00:00"),
    )

    # Eight pages, well past the five the sweep used to stop at.
    assert seen == [1, 2, 3, 4, 5, 6, 7, 8]
    assert len(resources) == 7


async def test_a_feed_that_ignores_the_page_number_does_not_loop():
    seen: list[int] = []

    class FakeAnimeGarden:
        async def search_resources(self, *, page, **kwargs):
            seen.append(page)
            return [_feed_resource(1, "[ANi] Test Anime - 01 [简][1080p]")], False

    await SubscriptionWorker(
        anime_garden=FakeAnimeGarden(),
        bangumi=FakeBangumi(),
    )._fetch_subject_history(
        _subject_subscription(),
        datetime.fromisoformat("2026-08-20T12:00:00"),
    )

    # The second page repeats the first, which is as good as the end of the feed.
    assert seen == [1, 2]


async def test_the_subject_id_is_asked_by_itself_without_any_name():
    calls: list[dict] = []

    class FakeAnimeGarden:
        async def search_resources(self, **kwargs):
            calls.append(kwargs)
            return [_episode_resource(1, 1, "2026-08-01")], True

    subscription = SimpleNamespace(
        anime=Anime(
            id=1,
            bangumi_id=4242,
            name="Official Name",
            name_cn="中文名",
            aliases=["俗称"],
        ),
        cursor_at=None,
        backfill_after=None,
        search_keywords=[],
        use_subject_id=True,
        resource_types=["动画"],
    )

    await SubscriptionWorker(anime_garden=FakeAnimeGarden())._fetch_subject_history(
        subscription,
        datetime.fromisoformat("2026-09-03T12:00:00"),
    )

    # ``subjectId`` upstream is the Bangumi id, so it is exact and complete on
    # its own -- name queries would only re-fetch what it already covers.
    assert len(calls) == 1
    assert calls[0]["subjects"] == (4242,)
    assert calls[0]["search"] == ()


@pytest.mark.parametrize(
    ("airdates", "expected"),
    [
        # A season that dates what it has published: an undated row is a future
        # episode, not one that quietly aired.
        (["2026-08-01", "2026-08-08", None], (1, 2)),
        # A season with no dates at all is an old subject, so all of it aired.
        ([None, None, None], (1, 2, 3)),
        (["2026-08-01", "2026-09-30"], (1,)),
    ],
)
def test_aired_episodes_only_trust_dates_when_the_season_has_them(airdates, expected):
    episodes = [
        EpisodeInfo(ep=index + 1, sort=index + 1, airdate=value)
        for index, value in enumerate(airdates)
    ]
    assert (
        aired_episode_indices(episodes, datetime.fromisoformat("2026-08-20T12:00:00"))
        == expected
    )


def _episode_resource(resource_id: int, index: int, airdate: str) -> AnimeGardenResource:
    return AnimeGardenResource(
        id=resource_id,
        provider="test",
        provider_id=str(resource_id),
        title=f"[ANi] Test Anime - {index:02d} [简][1080p][AVC]",
        type="动画",
        magnet=f"magnet:?xt=urn:btih:{resource_id}",
        tracker="",
        size=100,
        fansub_name="ANi",
        publisher_name="",
        # An hour after broadcast: an earlier resource would be rejected as a
        # mis-parse of an episode that had not aired yet.
        created_at=datetime.fromisoformat(f"{airdate}T01:00:00"),
        subject_ids=frozenset({4242}),
    )


async def test_preview_reports_the_aired_season_and_the_episodes_rules_miss():
    airdates = [
        "2026-08-01",
        "2026-08-08",
        "2026-08-15",
        "2026-08-22",
        "2026-08-29",
        "2026-09-05",
    ]
    calls: list[dict] = []

    class FakeAnimeGarden:
        async def search_resources(self, **kwargs):
            calls.append(kwargs)
            # Episode 5 aired, but nobody published anything for it.
            return [
                _episode_resource(index + 1, index + 1, airdates[index])
                for index in range(4)
            ], True

    class FakeBangumi:
        async def get_subject(self, subject_id):
            return None

        async def get_episodes(self, subject_id):
            return [
                EpisodeInfo(ep=index + 1, sort=index + 1, airdate=value)
                for index, value in enumerate(airdates)
            ]

    anime = Anime(
        id=1,
        bangumi_id=4242,
        name="Test Anime",
        name_cn="测试",
        air_date="2026-08-01",
        episode_count=6,
        episodes=[],
    )
    draft = SimpleNamespace(
        backfill_aired=True,
        fansub="ANi",
        allow_no_fansub=False,
        search_keywords=[],
        must_include=[],
        exclude_keywords=[],
        use_subject_id=True,
        resource_types=["动画"],
        profile_overrides=None,
        episode_offset_override=None,
    )

    result = await SubscriptionWorker(
        anime_garden=FakeAnimeGarden(),
        bangumi=FakeBangumi(),
    ).preview(
        anime=anime,
        profile=PreferenceProfile(name="默认", is_default=True),
        draft=draft,
        now=datetime.fromisoformat("2026-09-03T12:00:00"),
    )

    assert result["episode_count"] == 6
    assert result["aired_episode_count"] == 5
    assert result["owned_episode_count"] == 0
    assert result["matched_episodes"] == [1, 2, 3, 4]
    # The whole reason the editor shows this: "no candidate for episode 5" and
    # "episode 6 has not aired" are different answers.
    assert result["missing_episodes"] == [5]
    # No window at all, exactly as a real check fetches. A preview reading a
    # narrower window than the worker would promise less than the worker finds,
    # which is the drift this module exists to avoid.
    assert calls[0]["after"] is None


async def test_a_subject_query_asks_for_the_whole_history_not_a_window():
    calls: list[dict] = []

    class FakeAnimeGarden:
        async def search_resources(self, **kwargs):
            calls.append(kwargs)
            return [], True

    subscription = SimpleNamespace(
        anime=Anime(id=1, bangumi_id=4242, name="作品", name_cn="作品"),
        cursor_at=datetime.fromisoformat("2026-09-01T00:00:00"),
        backfill_after=datetime.fromisoformat("2026-07-31T00:00:00"),
        search_keywords=[],
        use_subject_id=True,
        resource_types=["动画"],
    )

    await SubscriptionWorker(
        anime_garden=FakeAnimeGarden(),
        bangumi=FakeBangumi(),
    )._fetch_subject_history(
        subscription,
        datetime.fromisoformat("2026-09-03T12:00:00"),
    )

    # Upstream's ``after`` filters on publish time, but the index frequently
    # only learns of a release weeks later -- such a release is born behind any
    # cursor and no window can bring it back. A subject query needs none: it
    # answers with the show's entire history in one complete page. This is what
    # the backfill window was reaching for, and it supersedes it.
    assert calls[0]["after"] is None


async def test_subscribing_queues_the_first_check_instead_of_waiting_for_a_sweep(
    client,
    auth_headers,
    monkeypatch,
):
    queued: list[int] = []
    monkeypatch.setattr(
        routes_subscriptions,
        "BangumiService",
        lambda: _FakeBangumiSubjects(),
    )
    monkeypatch.setattr(
        routes_subscriptions,
        "request_initial_check",
        queued.append,
    )
    user_headers = await auth_headers(PermissionGroup.USER)

    created = client.post(
        "/api/v1/subscriptions",
        json={"bangumi_id": 4242, "fansub": "ANi", "backfill_aired": True},
        headers=user_headers,
    )

    assert created.status_code == 201, created.text
    subscription = created.json()
    # Following a show is a request to fetch it: the download must not wait up
    # to a full sweep interval.
    assert queued == [subscription["id"]]
    # And it needs no catch-up window to reach the episodes already aired: the
    # check reads the show's whole history either way.
    assert subscription["backfill_after"] is None


class _FakeBangumiSubjects:
    async def get_subject(self, subject_id: int):
        return SubjectInfo(
            bangumi_id=subject_id,
            name="Placeholder Anime",
            name_cn="占位番剧",
            image_url="https://example.invalid/cover.jpg",
            episode_count=12,
            air_date="2026-08-12",
        )

    async def get_episodes(self, subject_id: int):
        return [
            EpisodeInfo(
                ep=index,
                sort=index,
                name_cn="第$index集",
                airdate=f"2026-08-{11 + index:02d}",
            )
            for index in range(1, 13)
        ]


async def test_a_second_query_is_not_abandoned_over_its_overlap_with_the_first():
    seen: list[tuple[tuple[int, ...], int]] = []

    class FakeAnimeGarden:
        async def search_resources(self, *, page, subjects=(), **kwargs):
            seen.append((tuple(subjects), page))
            if tuple(subjects) == (1,):
                return [_feed_resource(1, "[ANi] 作品 - 01 [简][1080p]")], True
            if page == 1:
                # The very release the first query already contributed.
                return [_feed_resource(1, "[ANi] 作品 - 01 [简][1080p]")], False
            return [_feed_resource(2, "[ANi] 作品 - 02 [简][1080p]")], True

    resources = await SubscriptionWorker(
        anime_garden=FakeAnimeGarden(),
        bangumi=FakeBangumi(),
    )._fetch_resources(
        after=datetime.fromisoformat("2026-08-13T12:00:00"),
        before=datetime.fromisoformat("2026-08-20T12:00:00"),
        queries=(
            worker_module._Query(subjects=(1,)),
            worker_module._Query(subjects=(2,)),
        ),
    )

    # Overlap between queries is ordinary -- one release is indexed under more
    # than one subject -- and must not read as "this query has no more pages".
    assert [page for subjects, page in seen if subjects == (2,)] == [1, 2]
    assert {resource.id for resource in resources} == {1, 2}


@pytest.mark.parametrize(
    ("title", "expected"),
    (
        # A v2 re-release glues the version straight onto the count.
        ("[绿茶字幕组] 无职转生 第三季 / Mushoku Tensei S3 [02v2][WebRip][1080p][简繁日内封]", 2),
        # Full-width brackets are what many Chinese groups actually ship.
        ("【极影字幕社】 ★7月新番【死神 千年血战 祸进谭】【Bleach】【44】GB MP4_720P", 44),
        # 搬运 reposts write the count against the title with no separator.
        ("[搬运][Erai-raws]最强废渣王子暗中活跃于帝位之争07 1080P 简繁中字", 7),
        # Long runners are well past three digits.
        ("[Skymoon-Raws][One Piece 海賊王][1174][ViuTV][WEB-RIP][CHT][1080p][MKV]", 1174),
        # The end marker sits inside the brackets, ahead of the closer.
        ("[GM-Team][国漫][神墓 第3季][Tomb of Fallen Gods Ⅲ][2025][52 END][GB][4K HEVC 10Bit]", 52),
        # 第2季 is a season. Read as episode 2 it did worse than fail: every
        # episode of the season claimed episode 2's slot, and the episode the
        # title really carries was never recorded at all.
        ("[GM-Team][国漫][逆天邪神 第2季][Against the Gods Ⅱ][2026][20][HEVC][GB][4K]", 20),
        ("[黒ネズミたち] 一人之下 第6季 / The Outcast 6 - 26 (CR 2600x1080 AVC AAC MKV)", 26),
        # A production year is not an episode number.
        ("[GM-Team][国漫][记忆管理局][The Memory Bureau][2026][03][AVC][GB][1080P]", 3),
    ),
)
def test_real_world_title_forms_yield_their_episode_number(title, expected):
    assert _extract_episode_number(title)[0] == expected


@pytest.mark.parametrize(
    "title",
    (
        # Four-digit batches. ``1158-1159`` used to lose its front half to the
        # date rule -- "year 1158, month 11" -- and pass the leftover 59 off as
        # an episode number.
        "[OPFans楓雪動漫][ONE PIECE 海賊王][第23季][1158-1159][1080P][MP4][周日版]",
        "[咪路fans制作组]蜡笔小新 Crayonshinchan [1338-1343][1080P][GB][MP4]",
        "[愛戀字幕社][7月新番][奇招百出的維多利亞][01-05][1080P][MP4][BIG5][繁中]",
    ),
)
def test_multi_episode_batches_are_not_passed_off_as_one_episode(title):
    number, _, reason = _extract_episode_number(title)
    assert number is None
    assert reason == "集数区间资源"


def test_a_broadcast_date_is_still_not_read_as_an_episode_number():
    # 1543 is the episode; neither the 08 nor the 16 of the date may win.
    assert _extract_episode_number(
        "[丸子家族][樱桃小丸子第二期(Chibi Maruko-chan II)][1543]"
        "户川老师做暑假作业[2026.08.16][GB][1080P][MP4]"
    )[0] == 1543


async def test_the_subject_history_is_fetched_without_a_window_or_an_early_stop():
    calls: list[dict] = []

    class FakeAnimeGarden:
        async def search_resources(self, **kwargs):
            calls.append(kwargs)
            return [_feed_resource(1, "[ANi] 作品 - 01 [简][1080p]")], True

    subscription = SimpleNamespace(
        anime=Anime(id=1, bangumi_id=4242, name="作品", name_cn="作品"),
        cursor_at=datetime.fromisoformat("2026-09-01T00:00:00"),
        backfill_after=None,
        search_keywords=[],
        use_subject_id=True,
        resource_types=["动画"],
    )

    resources = await SubscriptionWorker(
        anime_garden=FakeAnimeGarden(),
        bangumi=FakeBangumi(),
    )._fetch_subject_history(
        subscription,
        datetime.fromisoformat("2026-09-03T12:00:00"),
    )

    assert len(calls) == 1
    assert calls[0]["after"] is None
    assert calls[0]["subjects"] == (4242,)
    assert [resource.id for resource in resources] == [1]


async def test_no_subject_to_ask_by_means_no_history_request_at_all():
    class FakeAnimeGarden:
        async def search_resources(self, **kwargs):
            raise AssertionError("nothing to ask by, so nothing should be asked")

    subscription = SimpleNamespace(
        anime=Anime(id=1, bangumi_id=0, name="作品", name_cn="作品"),
        cursor_at=None,
        backfill_after=None,
        search_keywords=[],
        resource_types=["动画"],
    )

    assert await SubscriptionWorker(
        anime_garden=FakeAnimeGarden(),
        bangumi=FakeBangumi(),
    )._fetch_subject_history(
        subscription, datetime.fromisoformat("2026-09-03T12:00:00")
    ) == []
