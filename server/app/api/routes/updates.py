from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException

from app.core.auth import require_admin
from app.core.config import config, save_config
from app.core.constants import SERVER_VERSION
from app.schemas import (
    ServerUpdateChannelRead,
    ServerUpdateChannelUpdate,
    ServerUpdateRead,
    ServerUpdateRequest,
    ServerUpdateStatusRead,
)
from app.schemas.update import UpdateChannel
from app.services.server_update_service import server_update_service

router = APIRouter(prefix="/updates", tags=["updates"])


@router.get("", response_model=ServerUpdateRead)
async def get_update(channel: UpdateChannel | None = None, _=Depends(require_admin)):
    channel = channel or _configured_channel()
    try:
        candidate = await server_update_service.get_candidate(channel)
    except RuntimeError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc
    return ServerUpdateRead(
        channel=candidate.channel,
        current_version=_current_version(candidate.channel),
        latest_version=candidate.version,
        release_name=candidate.name,
        release_notes=candidate.notes,
        published_at=candidate.published_at,
        release_url=candidate.release_url,
        update_available=not _versions_equal(
            candidate.version,
            _current_version(candidate.channel),
        ),
    )


@router.post("", status_code=202)
async def apply_update(
    payload: ServerUpdateRequest,
    background_tasks: BackgroundTasks,
    _=Depends(require_admin),
):
    state = server_update_service.begin_update(payload.channel)
    if state is None:
        raise HTTPException(status_code=409, detail="已有更新任务正在执行")
    background_tasks.add_task(server_update_service.apply_update, payload.channel)
    return state


@router.get("/channel", response_model=ServerUpdateChannelRead)
async def get_update_channel(_=Depends(require_admin)):
    return ServerUpdateChannelRead(channel=_configured_channel())


@router.put("/channel", response_model=ServerUpdateChannelRead)
async def update_update_channel(
    payload: ServerUpdateChannelUpdate,
    _=Depends(require_admin),
):
    config["updates"]["channel"] = payload.channel
    await save_config(config)
    return ServerUpdateChannelRead(channel=payload.channel)


@router.get("/status", response_model=ServerUpdateStatusRead)
async def get_update_status(_=Depends(require_admin)):
    return server_update_service.update_status()


def _versions_equal(left: str, right: str) -> bool:
    return left.removeprefix("v") == right.removeprefix("v")


def _current_version(channel: UpdateChannel) -> str:
    if channel == UpdateChannel.BRANCH:
        return server_update_service.current_build_commit() or "未记录"
    return SERVER_VERSION


def _configured_channel() -> UpdateChannel:
    try:
        return UpdateChannel(config["updates"].get("channel", UpdateChannel.RELEASE))
    except ValueError:
        return UpdateChannel.RELEASE
