from app.schemas.anime import (
    AnimeCreate,
    AnimeRead,
    BangumiInfoItem,
    EpisodeCreate,
    EpisodeRead,
    WatchProgressRead,
    WatchProgressUpdate,
)
from app.schemas.auth import Token
from app.schemas.config import QBittorrentConfigRead, QBittorrentConfigUpdate
from app.schemas.qbittorrent import (
    QBittorrentFileRead,
    QBittorrentTorrentAdd,
    QBittorrentTorrentAddResult,
    QBittorrentTorrentDownload,
)
from app.schemas.setup import SetupCreate, SetupStatus
from app.schemas.user import UserCreate, UserRead, UserUpdate

__all__ = [
    "AnimeCreate",
    "AnimeRead",
    "BangumiInfoItem",
    "EpisodeCreate",
    "EpisodeRead",
    "QBittorrentConfigRead",
    "QBittorrentConfigUpdate",
    "QBittorrentFileRead",
    "QBittorrentTorrentAdd",
    "QBittorrentTorrentAddResult",
    "QBittorrentTorrentDownload",
    "SetupCreate",
    "SetupStatus",
    "Token",
    "WatchProgressRead",
    "WatchProgressUpdate",
    "UserCreate",
    "UserRead",
    "UserUpdate",
]
