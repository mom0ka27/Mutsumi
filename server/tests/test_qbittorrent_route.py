import httpx
from typing import cast

from app.api.routes import qbittorrent
from app.api.routes.qbittorrent import _related_subtitle_names
from app.models import User
from app.schemas import QBittorrentFileRead, QBittorrentTorrentDownload


def test_related_subtitle_names_selects_same_directory_video_subtitles():
    files = [
        QBittorrentFileRead(name="Season/[Group] Title - 01.mkv", size=1),
        QBittorrentFileRead(name="Season/[Group] Title - 01.ass", size=1),
        QBittorrentFileRead(name="Season/[Group] Title - 01.zh-Hans.VTT", size=1),
        QBittorrentFileRead(name="Season/[Group] Title - 02.srt", size=1),
        QBittorrentFileRead(name="Other/[Group] Title - 01.ssa", size=1),
    ]

    result = _related_subtitle_names(files, {"Season/[Group] Title - 01.mkv"})

    assert result == {
        "Season/[Group] Title - 01.ass",
        "Season/[Group] Title - 01.zh-Hans.VTT",
    }


async def test_download_existing_torrent_enables_selected_files(monkeypatch):
    class Client:
        async def aclose(self):
            return None

    client = Client()
    calls = []

    async def fake_client(timeout=10):
        return client

    async def fake_wait_for_metadata(_client, source):
        return {
            "hash": "abc123",
            "info": {
                "files": [
                    {"name": "Show/01.mkv", "size": 100},
                    {"name": "Show/02.mkv", "size": 100},
                ]
            },
        }

    async def fake_get(_client, url, params=None):
        assert url == "/api/v2/torrents/info"
        assert params == {"hashes": "abc123"}
        request = httpx.Request("GET", "http://test/api/v2/torrents/info")
        return httpx.Response(200, json=[{"hash": "abc123"}], request=request)

    async def fake_post(_client, url, data):
        calls.append((url, data))
        request = httpx.Request("POST", f"http://test{url}")
        return httpx.Response(200, text="Ok.", request=request)

    monkeypatch.setattr(qbittorrent, "_qbittorrent_client", fake_client)
    monkeypatch.setattr(qbittorrent, "_wait_for_metadata", fake_wait_for_metadata)
    monkeypatch.setattr(qbittorrent, "_qbittorrent_get", fake_get)
    monkeypatch.setattr(qbittorrent, "_qbittorrent_post", fake_post)

    result = await qbittorrent.download_torrent_files(
        QBittorrentTorrentDownload(
            source="magnet:?xt=urn:btih:abc123",
            filenames=["Show/02.mkv"],
        ),
        cast(User, None),
    )

    assert result.hash == "abc123"
    assert calls == [
        (
            "/api/v2/torrents/filePrio",
            {"hash": "abc123", "id": "1", "priority": "1"},
        )
    ]


async def test_download_new_torrent_adds_with_file_priorities(monkeypatch):
    class Client:
        async def aclose(self):
            return None

    client = Client()
    calls = []

    async def fake_client(timeout=10):
        return client

    async def fake_wait_for_metadata(_client, source):
        return {
            "hash": "abc123",
            "info": {
                "files": [
                    {"name": "Show/01.mkv", "size": 100},
                    {"name": "Show/02.mkv", "size": 100},
                ]
            },
        }

    async def fake_get(_client, url, params=None):
        request = httpx.Request("GET", "http://test/api/v2/torrents/info")
        return httpx.Response(200, json=[], request=request)

    async def fake_post(_client, url, data):
        calls.append((url, data))
        request = httpx.Request("POST", f"http://test{url}")
        return httpx.Response(200, text="Ok.", request=request)

    monkeypatch.setattr(qbittorrent, "_qbittorrent_client", fake_client)
    monkeypatch.setattr(qbittorrent, "_wait_for_metadata", fake_wait_for_metadata)
    monkeypatch.setattr(qbittorrent, "_qbittorrent_get", fake_get)
    monkeypatch.setattr(qbittorrent, "_qbittorrent_post", fake_post)

    result = await qbittorrent.download_torrent_files(
        QBittorrentTorrentDownload(
            source="magnet:?xt=urn:btih:abc123",
            filenames=["Show/02.mkv"],
        ),
        cast(User, None),
    )

    assert result.hash == "abc123"
    assert len(calls) == 1
    assert calls[0][0] == "/api/v2/torrents/add"
    assert calls[0][1]["filePriorities"] == "0,1"
