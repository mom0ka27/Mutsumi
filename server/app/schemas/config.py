from pydantic import BaseModel, Field


class QBittorrentConfigRead(BaseModel):
    url: str
    username: str
    download_path: str
    password_configured: bool


class QBittorrentConfigUpdate(BaseModel):
    url: str = Field(default="")
    username: str = Field(default="")
    password: str = Field(default="")
    download_path: str = Field(default="")
