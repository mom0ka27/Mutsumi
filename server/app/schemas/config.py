from pydantic import BaseModel, Field


class QBittorrentConfigRead(BaseModel):
    url: str
    username: str
    download_path: str
    password_configured: bool
    share_ratio_limit: float


class QBittorrentConfigUpdate(BaseModel):
    url: str = Field(default="")
    username: str = Field(default="")
    password: str | None = Field(default=None)
    download_path: str = Field(default="")
    share_ratio_limit: float = Field(default=3.0, ge=-1)
