from fastapi import APIRouter, Depends

from app.core.auth import require_admin
from app.core.config import config, save_config
from app.schemas import QBittorrentConfigRead, QBittorrentConfigUpdate

router = APIRouter(
    prefix="/config",
    tags=["config"],
    dependencies=[Depends(require_admin)],
)


@router.get("/qbittorrent", response_model=QBittorrentConfigRead)
async def get_qbittorrent_config():
    return _qbittorrent_config_read()


@router.put("/qbittorrent", response_model=QBittorrentConfigRead)
async def update_qbittorrent_config(payload: QBittorrentConfigUpdate):
    config["qbittorrent"] = {
        "url": payload.url.strip().rstrip("/"),
        "username": payload.username.strip(),
        "password": payload.password
        if payload.password is not None
        else config["qbittorrent"].get("password", ""),
        "download_path": payload.download_path.strip(),
        "share_ratio_limit": payload.share_ratio_limit,
    }
    await save_config(config)

    return _qbittorrent_config_read()


def _qbittorrent_config_read() -> QBittorrentConfigRead:
    qbittorrent_config = config["qbittorrent"]
    return QBittorrentConfigRead(
        url=qbittorrent_config.get("url") or "",
        username=qbittorrent_config.get("username") or "",
        download_path=qbittorrent_config.get("download_path") or "",
        password_configured=bool(qbittorrent_config.get("password")),
        share_ratio_limit=float(qbittorrent_config.get("share_ratio_limit", 3.0)),
    )
