from enum import StrEnum

from pydantic import BaseModel


class UpdateChannel(StrEnum):
    RELEASE = "release"
    PRERELEASE = "prerelease"
    BRANCH = "branch"


class UpdateStatus(StrEnum):
    DOWNLOADING = "downloading"
    INSTALLING = "installing"
    RUNNING = "running"
    FAILED = "failed"


class ServerUpdateRead(BaseModel):
    channel: UpdateChannel
    current_version: str
    latest_version: str
    release_name: str
    release_notes: str
    published_at: str | None
    release_url: str
    update_available: bool


class ServerUpdateChannelRead(BaseModel):
    channel: UpdateChannel


class ServerUpdateChannelUpdate(BaseModel):
    channel: UpdateChannel


class ServerUpdateRequest(BaseModel):
    channel: UpdateChannel


class ServerUpdateStatusRead(BaseModel):
    status: UpdateStatus
    channel: UpdateChannel | None
    target_version: str
    message: str
