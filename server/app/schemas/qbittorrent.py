from pydantic import BaseModel

class QBittorrentTorrentDownload(BaseModel):
    source: str
    filenames: list[str]


class QBittorrentTorrentAddResult(BaseModel):
    hash: str


class QBittorrentFileRead(BaseModel):
    name: str
    size: int


class QBittorrentTorrentRead(BaseModel):
    hash: str
    name: str
    state: str
    progress: float
    total_size: int
    downloaded: int
    amount_left: int
    dlspeed: int
    upspeed: int
    eta: int
