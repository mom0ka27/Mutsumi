from pydantic import BaseModel


class QBittorrentTorrentAdd(BaseModel):
    url: str


class QBittorrentTorrentDownload(BaseModel):
    source: str
    filenames: list[str]


class QBittorrentTorrentAddResult(BaseModel):
    hash: str


class QBittorrentFileRead(BaseModel):
    name: str
    size: int
