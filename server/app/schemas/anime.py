from pydantic import BaseModel, ConfigDict, Field


class BangumiInfoItem(BaseModel):
    key: str
    value: str


class EpisodeCreate(BaseModel):
    index: int
    name: str = ""
    filename: str = ""


class EpisodeRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    index: int
    name: str
    filename: str


class WatchProgressUpdate(BaseModel):
    episode_id: int | None = None
    position_seconds: int = 0


class WatchProgressRead(BaseModel):
    episode_id: int | None = None
    position_seconds: int = 0


class AnimeCreate(BaseModel):
    bangumi_id: int
    name: str
    name_cn: str = ""
    summary: str = ""
    image_url: str = ""
    score: float = 0
    episode_count: int = 0
    air_date: str = ""
    rank: int = 0
    platform: str = ""
    tags: list[str] = Field(default_factory=list)
    infobox: list[BangumiInfoItem] = Field(default_factory=list)
    download_hash: str | None = None
    episodes: list[EpisodeCreate] | None = None


class AnimeRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    bangumi_id: int
    name: str
    name_cn: str
    summary: str
    image_url: str
    score: float
    episode_count: int
    air_date: str
    rank: int
    platform: str
    tags: list[str]
    infobox: list[BangumiInfoItem]
    download_hash: str | None
    episodes: list[EpisodeRead]
    watch_progress: WatchProgressRead | None = None
