from datetime import datetime
from types import SimpleNamespace

import pytest

from app.models import PermissionGroup
from app.models import Anime, Episode, PreferenceProfile, Subscription
from app.schemas.qbittorrent import QBittorrentFileRead, QBittorrentTorrentAddResult
from app.services.animegarden_service import AnimeGardenResource
from app.api.routes import subscriptions as routes_subscriptions
from app.services.bangumi_service import SubjectInfo
from app.services.subscription_engine import (
    EpisodeInfo,
    aired_episode_indices,
    derive_airing_status,
    evaluate_resource,
    parse_episode_index,
    parse_title_attributes,
    profile_values,
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
        SubscriptionRules(bangumi_id=4242, fansubs=("ANi",)),
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
        SubscriptionRules(bangumi_id=4242, fansubs=("ANi",)),
    )

    assert result.accepted is False
    assert result.reason in {"集数区间资源", "合集或批量资源"}


def test_fansub_dimension_is_neutral_when_nothing_was_selected():
    profile = profile_values(None)

    result = evaluate_resource(
        Resource("[ANi] 作品 - 01 [简][1080p][AVC]"),
        profile,
        SubscriptionRules(bangumi_id=4242, fansubs=(), allow_no_fansub=True),
    )

    assert result.accepted is True
    # Zero here would cap the total at 0.55 and make accept_now unreachable.
    assert result.component_scores["fansub"] == profile.neutral_score
    assert result.score > profile.neutral_score


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

    await SubscriptionWorker(anime_garden=FakeAnimeGarden())._fetch_targeted_resources(
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
            "fansubs": ["ANi"],
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


async def test_subscription_preview_selects_the_highest_scored_candidate():
    class FakeAnimeGarden:
        async def search_resources(self, **kwargs):
            return [
                AnimeGardenResource(
                    id=1,
                    provider="test",
                    provider_id="1",
                    title="[ANi] Test Anime - 01 [简][1080p][avc]",
                    type="动画",
                    magnet="magnet:?xt=urn:btih:test",
                    tracker="",
                    size=100,
                    fansub_name="ANi",
                    publisher_name="",
                    created_at=datetime.fromisoformat("2026-08-20T10:00:00"),
                    subject_ids=frozenset({4242}),
                ),
                AnimeGardenResource(
                    id=2,
                    provider="test",
                    provider_id="2",
                    title="[Other] Test Anime - 01 [简][720p][avc]",
                    type="动画",
                    magnet="magnet:?xt=urn:btih:test2",
                    tracker="",
                    size=100,
                    fansub_name="Other",
                    publisher_name="",
                    created_at=datetime.fromisoformat("2026-08-20T10:01:00"),
                    subject_ids=frozenset({4242}),
                ),
            ], True

    class FakeBangumi:
        async def get_episodes(self, subject_id):
            return [EpisodeInfo(ep=1, sort=1, name_cn="第一集", airdate="2026-08-19")]

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
        fansubs=["ANi", "Other"],
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


@pytest.mark.parametrize(
    ("air_date", "airdates", "expected"),
    [
        # Bangumi has no status field, so it is derived. An unaired show
        # usually has no episode rows at all -- that case must not read as
        # "finished" just because the episode list is empty.
        ("2026-10-07", [], "unaired"),
        ("2026-08-12", ["2026-08-12", "2026-09-30"], "airing"),
        ("2023-09-29", ["2023-09-29", "2024-03-22"], "finished"),
        ("2015-01-01", [], "finished"),
        ("", ["2024-03-22"], "finished"),
        ("", [], "unknown"),
    ],
)
def test_airing_status_is_derived_from_dates(air_date, airdates, expected):
    episodes = [
        EpisodeInfo(ep=index + 1, sort=index + 1, airdate=value)
        for index, value in enumerate(airdates)
    ]

    status = derive_airing_status(
        air_date,
        episodes,
        now=datetime.fromisoformat("2026-08-21T12:00:00"),
    )

    assert status == expected


def test_missing_episode_table_defers_instead_of_needing_review():
    result = parse_episode_index(
        "[ANi] 作品 - 01 [1080p]",
        [],
        datetime.fromisoformat("2026-08-20T12:00:00"),
    )

    assert result.index is None
    assert result.deferred is True
    assert "尚无集数表" in result.reason


async def test_deferred_rows_rejoin_the_pool_once_bangumi_publishes_episodes():
    row = worker_module.SubscriptionEpisode(
        subscription_id=1,
        episode_index=None,
        resource_id=5,
        resource_title="[ANi] 作品 - 01 [1080p]",
        score=0.9,
        attributes={"created_at": "2026-08-20T10:00:00"},
        state="deferred",
        first_seen_at=datetime.fromisoformat("2026-08-20T10:00:00"),
    )

    class FakeSession:
        async def scalars(self, *_args, **_kwargs):
            return [row]

    await SubscriptionWorker()._retry_deferred(
        FakeSession(),
        Subscription(id=1, episode_offset_override=None),
        [EpisodeInfo(ep=1, sort=1, name_cn="第一集", airdate="2026-08-19")],
        Anime(id=1, bangumi_id=4242, name="作品"),
    )

    assert row.state == "candidate"
    assert row.episode_index == 1
    # The waiting window must not restart just because the row was deferred.
    assert row.first_seen_at == datetime.fromisoformat("2026-08-20T10:00:00")


async def test_subscribing_creates_a_placeholder_that_is_not_library_content(
    client,
    auth_headers,
    monkeypatch,
):
    monkeypatch.setattr(
        routes_subscriptions,
        "BangumiService",
        lambda: _FakeBangumiSubjects(),
    )
    user_headers = await auth_headers(PermissionGroup.USER)

    created = client.post(
        "/api/v1/subscriptions",
        json={"bangumi_id": 4242, "fansubs": ["ANi"]},
        headers=user_headers,
    )
    assert created.status_code == 201, created.text
    subscription = created.json()
    assert subscription["anime_name_cn"] == "占位番剧"
    assert subscription["bangumi_id"] == 4242
    # The home section needs an expected date right away, not after a sweep.
    assert subscription["next_episode_index"] == 1
    assert subscription["next_episode_air_date"].startswith("2026-08-12")
    assert subscription["episode_count"] == 12
    assert subscription["owned_episode_count"] == 0
    assert subscription["needs_review_count"] == 0

    # Reachable by id, and through the subscription list...
    detail = client.get(
        f"/api/v1/anime/{subscription['anime_id']}", headers=user_headers
    )
    assert detail.status_code == 200
    assert detail.json()["episode_count"] == 12
    # ...but not library content, so it never shows up as an empty card,
    # nor as a zero-byte row on the storage page.
    library = client.get("/api/v1/anime", headers=user_headers)
    assert library.status_code == 200
    assert library.json() == []
    storage = client.get(
        "/api/v1/storage", headers=await auth_headers(PermissionGroup.ADMIN)
    )
    assert storage.status_code == 200, storage.text
    assert storage.json()["anime"] == []

    removed = client.delete(
        f"/api/v1/subscriptions/{subscription['id']}", headers=user_headers
    )
    assert removed.status_code == 204
    assert (
        client.get(
            f"/api/v1/anime/{subscription['anime_id']}", headers=user_headers
        ).status_code
        == 404
    )


async def test_download_after_subscribing_merges_into_the_placeholder(
    client,
    auth_headers,
    monkeypatch,
):
    monkeypatch.setattr(
        routes_subscriptions,
        "BangumiService",
        lambda: _FakeBangumiSubjects(),
    )
    user_headers = await auth_headers(PermissionGroup.USER)
    created = client.post(
        "/api/v1/subscriptions",
        json={"bangumi_id": 4242, "fansubs": ["ANi"]},
        headers=user_headers,
    )
    assert created.status_code == 201, created.text
    anime_id = created.json()["anime_id"]

    # The manual download flow posts the whole subject again. A 409 here would
    # abort a perfectly valid download.
    merged = client.post(
        "/api/v1/anime",
        json={
            "bangumi_id": 4242,
            "name": "Placeholder",
            "name_cn": "占位番剧",
            "download_hash": "b" * 40,
            "episodes": [{"index": 1, "name": "第一集", "filename": "01.mkv"}],
        },
        headers=user_headers,
    )
    assert merged.status_code == 201, merged.text
    assert merged.json()["id"] == anime_id
    assert [episode["index"] for episode in merged.json()["episodes"]] == [1]

    # Now it has a file, so it is library content.
    library = client.get("/api/v1/anime", headers=user_headers)
    assert [item["id"] for item in library.json()] == [anime_id]

    # And cancelling the subscription must leave the downloaded anime alone.
    subscription_id = created.json()["id"]
    assert (
        client.delete(
            f"/api/v1/subscriptions/{subscription_id}", headers=user_headers
        ).status_code
        == 204
    )
    assert (
        client.get(f"/api/v1/anime/{anime_id}", headers=user_headers).status_code == 200
    )


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
        fansubs=["ANi"],
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
    # ``backfill_aired`` has to reach past the cold-start window, or a
    # mid-season preview would only ever see the last few days.
    assert calls[0]["after"] <= datetime.fromisoformat("2026-07-31T00:00:00")


async def test_first_check_prefers_the_backfill_window_over_the_cursor():
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

    await SubscriptionWorker(anime_garden=FakeAnimeGarden())._fetch_targeted_resources(
        subscription,
        datetime.fromisoformat("2026-09-03T12:00:00"),
    )

    assert calls[0]["after"] == datetime.fromisoformat("2026-07-31T00:00:00")


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
        json={"bangumi_id": 4242, "fansubs": ["ANi"], "backfill_aired": True},
        headers=user_headers,
    )

    assert created.status_code == 201, created.text
    subscription = created.json()
    # Following a show is a request to fetch it: the download must not wait up
    # to a full sweep interval.
    assert queued == [subscription["id"]]
    # And the queued check has a window that covers the episodes already aired.
    assert datetime.fromisoformat(
        subscription["backfill_after"]
    ) <= datetime.fromisoformat("2026-08-11T00:00:00")


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
