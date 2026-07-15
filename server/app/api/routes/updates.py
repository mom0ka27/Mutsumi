from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException

from app.core.auth import require_admin
from app.core.constants import SERVER_VERSION
from app.schemas import ServerUpdateRead, ServerUpdateRequest
from app.schemas.update import UpdateChannel
from app.services.server_update_service import server_update_service

router = APIRouter(prefix="/updates", tags=["updates"])


@router.get("", response_model=ServerUpdateRead)
async def get_update(channel: UpdateChannel, _=Depends(require_admin)):
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
    background_tasks.add_task(server_update_service.apply_update, payload.channel)
    return {"status": "updating"}


def _versions_equal(left: str, right: str) -> bool:
    return left.removeprefix("v") == right.removeprefix("v")


def _current_version(channel: UpdateChannel) -> str:
    if channel == UpdateChannel.BRANCH:
        return server_update_service.current_build_commit() or "未记录"
    return SERVER_VERSION
