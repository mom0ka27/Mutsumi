from app.api.routes.qbittorrent import _related_subtitle_names
from app.schemas import QBittorrentFileRead


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
