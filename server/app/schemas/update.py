from enum import StrEnum

from pydantic import BaseModel


class UpdateChannel(StrEnum):
    RELEASE = "release"
    PRERELEASE = "prerelease"
    BRANCH = "branch"


class ServerUpdateRead(BaseModel):
    channel: UpdateChannel
    current_version: str
    latest_version: str
    release_name: str
    release_notes: str
    published_at: str | None
    release_url: str
    update_available: bool
    integrity_verified: bool


class ServerUpdateRequest(BaseModel):
    channel: UpdateChannel
