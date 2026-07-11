from pathlib import Path

import asyncio
import re
from typing import Any

import httpx
from fastapi import APIRouter, Depends

from app.core.auth import get_current_user, require_download_permission
from app.core.config import config
from app.core.qbittorrent_error import QBittorrentError
from app.models import User
from app.schemas import (
    QBittorrentFileRead,
    QBittorrentTorrentAddResult,
    QBittorrentTorrentDownload,
    QBittorrentTorrentRead,
)

router = APIRouter(prefix="/qbittorrent", tags=["qbittorrent"])

_qbittorrent_cookies = httpx.Cookies()
_qbittorrent_cookie_lock = asyncio.Lock()
_qbittorrent_category = "Mutsumi"


@router.get("/torrents", response_model=list[QBittorrentTorrentRead])
async def get_torrents(_: User = Depends(get_current_user)):
    client = await _qbittorrent_client()
    try:
        response = await _qbittorrent_get(
            client,
            "/api/v2/torrents/info",
            params={
                "category": _qbittorrent_category,
                "sort": "added_on",
                "reverse": "true",
            },
        )
        if response.status_code >= 400:
            raise QBittorrentError(21004, "获取下载任务失败")
        data = response.json()
        if not isinstance(data, list):
            raise QBittorrentError(21004, "qBittorrent 返回了无效数据")
        return [_torrent_read(item) for item in data if isinstance(item, dict)]
    finally:
        await client.aclose()


@router.post("/torrents/download", response_model=QBittorrentTorrentAddResult)
async def download_torrent_files(
    payload: QBittorrentTorrentDownload,
    _: User = Depends(require_download_permission),
):
    selected_filenames = {filename for filename in payload.filenames if filename}
    if not selected_filenames:
        raise QBittorrentError(21010, "没有选择下载文件")

    client = await _qbittorrent_client(timeout=30)
    try:
        metadata = await _wait_for_metadata(client, payload.source)
        files = _metadata_files(metadata)
        if not files:
            raise QBittorrentError(21005, "种子元数据尚未就绪")

        torrent_hash = _metadata_hash(metadata) or _parse_bt_hash(payload.source) or ""
        save_path = _download_save_path(torrent_hash)
        file_priorities = ["1" if file.name in selected_filenames else "0" for file in files]
        add_data = {
            "urls": payload.source,
            "filePriorities": ",".join(file_priorities),
            "category": _qbittorrent_category,
            "ratioLimit": str(
                config["qbittorrent"].get("share_ratio_limit", 3.0)
            ),
        }
        if save_path:
            add_data["savepath"] = save_path

        response = await _qbittorrent_post(
            client,
            "/api/v2/torrents/add",
            data=add_data,
        )
        if response.status_code >= 400 or response.text.strip() == "Fails.":
            raise QBittorrentError(21006, "添加下载任务失败")
    finally:
        await client.aclose()

    if not torrent_hash:
        torrent_hash = _metadata_hash(metadata) or _parse_bt_hash(payload.source) or ""
    return QBittorrentTorrentAddResult(hash=torrent_hash)


@router.post("/torrents/{torrent_hash}/pause", status_code=204)
async def pause_torrent(
    torrent_hash: str,
    _: User = Depends(require_download_permission),
):
    client = await _qbittorrent_client()
    try:
        response = await _qbittorrent_post(
            client,
            "/api/v2/torrents/pause",
            data={"hashes": torrent_hash},
        )
        if response.status_code >= 400 or response.text.strip() == "Fails.":
            raise QBittorrentError(21007, "暂停下载任务失败")
    finally:
        await client.aclose()


@router.get("/torrents/metadata/files", response_model=list[QBittorrentFileRead])
async def get_torrent_metadata_files(
    source: str,
    _: User = Depends(get_current_user),
):
    client = await _qbittorrent_client()
    try:
        metadata = await _fetch_metadata(client, source)
    finally:
        await client.aclose()

    return _metadata_files(metadata)


@router.get("/torrents/{torrent_hash}/files", response_model=list[QBittorrentFileRead])
async def get_torrent_files(
    torrent_hash: str,
    _: User = Depends(get_current_user),
):
    client = await _qbittorrent_client()
    try:
        metadata = await _fetch_metadata(client, torrent_hash)
    finally:
        await client.aclose()

    return _metadata_files(metadata)


async def delete_torrent(torrent_hash: str) -> None:
    client = await _qbittorrent_client()
    try:
        response = await _qbittorrent_post(
            client,
            "/api/v2/torrents/delete",
            data={"hashes": torrent_hash, "deleteFiles": "true"},
        )
        if response.status_code >= 400 or response.text.strip() == "Fails.":
            raise QBittorrentError(21008, "删除下载任务或文件失败")
    finally:
        await client.aclose()


async def _wait_for_metadata(
    client: httpx.AsyncClient,
    source: str,
) -> dict:
    for attempt in range(20):
        metadata = await _fetch_metadata(client, source)
        if metadata.get("info"):
            return metadata
        if attempt < 19:
            await asyncio.sleep(1)
    return {}


async def _fetch_metadata(
    client: httpx.AsyncClient,
    source: str,
) -> dict:
    response = await _qbittorrent_post(
        client,
        "/api/v2/torrents/fetchMetadata",
        data={"source": source},
    )
    if response.status_code == 202:
        metadata = response.json()
        return metadata if isinstance(metadata, dict) else {}
    if response.status_code >= 400:
        raise QBittorrentError(21004, "获取种子元数据失败")

    metadata = response.json()
    return metadata if isinstance(metadata, dict) else {}


def _metadata_files(metadata: dict) -> list[QBittorrentFileRead]:
    info = metadata.get("info")
    if not isinstance(info, dict):
        return []

    files = info.get("files")
    if not isinstance(files, list):
        files = []
    if not files and info.get("name"):
        return [
            QBittorrentFileRead(
                name=str(info.get("name") or ""),
                size=int(info.get("length") or 0),
            )
        ]

    return [
        QBittorrentFileRead(
            name=str(file.get("name") or file.get("path") or ""),
            size=int(file.get("size") or file.get("length") or 0),
        )
        for file in files
        if isinstance(file, dict) and (file.get("name") or file.get("path"))
    ]


async def _qbittorrent_client(timeout: float = 10) -> httpx.AsyncClient:
    qbittorrent_config = config["qbittorrent"]
    url = (qbittorrent_config.get("url") or "").rstrip("/")
    if not url:
        raise QBittorrentError(21001, "qBittorrent 尚未配置")

    async with _qbittorrent_cookie_lock:
        cookies = httpx.Cookies(_qbittorrent_cookies)

    client = httpx.AsyncClient(base_url=url, timeout=timeout, cookies=cookies)
    try:
        if not _has_qbittorrent_cookie(client.cookies):
            await _qbittorrent_login(client)
        await _ensure_qbittorrent_category(client)
        return client
    except Exception:
        await client.aclose()
        raise


async def _qbittorrent_post(
    client: httpx.AsyncClient,
    url: str,
    data: dict[str, Any],
) -> httpx.Response:
    response = await client.post(url, data=data)
    await _save_qbittorrent_cookies(client)
    if response.status_code not in (401, 403):
        return response

    await _clear_qbittorrent_cookies()
    await _qbittorrent_login(client)
    response = await client.post(url, data=data)
    await _save_qbittorrent_cookies(client)
    return response


async def _qbittorrent_get(
    client: httpx.AsyncClient,
    url: str,
    params: dict[str, Any] | None = None,
) -> httpx.Response:
    response = await client.get(url, params=params)
    await _save_qbittorrent_cookies(client)
    if response.status_code not in (401, 403):
        return response

    await _clear_qbittorrent_cookies()
    await _qbittorrent_login(client)
    response = await client.get(url, params=params)
    await _save_qbittorrent_cookies(client)
    return response


def _torrent_read(item: dict) -> QBittorrentTorrentRead:
    return QBittorrentTorrentRead(
        hash=str(item.get("hash") or ""),
        name=str(item.get("name") or ""),
        state=str(item.get("state") or "unknown"),
        progress=float(item.get("progress") or 0),
        total_size=int(item.get("total_size") or item.get("size") or 0),
        downloaded=int(item.get("downloaded") or 0),
        amount_left=int(item.get("amount_left") or 0),
        dlspeed=int(item.get("dlspeed") or 0),
        upspeed=int(item.get("upspeed") or 0),
        eta=int(item.get("eta") or 0),
    )


async def _qbittorrent_login(client: httpx.AsyncClient) -> None:
    qbittorrent_config = config["qbittorrent"]
    username = qbittorrent_config.get("username") or ""
    password = qbittorrent_config.get("password") or ""

    response = await client.post(
        "/api/v2/auth/login",
        data={"username": username, "password": password},
    )
    await _save_qbittorrent_cookies(client)
    if response.status_code >= 400 or response.text.strip() == "Fails.":
        raise QBittorrentError(21003, "qBittorrent 登录失败")


async def _ensure_qbittorrent_category(client: httpx.AsyncClient) -> None:
    response = await _qbittorrent_get(client, "/api/v2/torrents/categories")
    if response.status_code >= 400:
        raise QBittorrentError(21009, "读取 qBittorrent 分类失败")
    categories = response.json()
    if isinstance(categories, dict) and _qbittorrent_category in categories:
        return
    response = await _qbittorrent_post(
        client,
        "/api/v2/torrents/createCategory",
        data={"category": _qbittorrent_category},
    )
    if response.status_code >= 400 or response.text.strip() == "Fails.":
        raise QBittorrentError(21009, "创建 Mutsumi 分类失败")


async def _save_qbittorrent_cookies(client: httpx.AsyncClient) -> None:
    async with _qbittorrent_cookie_lock:
        _qbittorrent_cookies.update(client.cookies)


async def _clear_qbittorrent_cookies() -> None:
    global _qbittorrent_cookies
    async with _qbittorrent_cookie_lock:
        _qbittorrent_cookies = httpx.Cookies()


def _has_qbittorrent_cookie(cookies: httpx.Cookies) -> bool:
    return cookies.get("SID") is not None


def _metadata_hash(metadata: dict) -> str | None:
    torrent_hash = metadata.get("hash") or metadata.get("infohash_v1")
    return str(torrent_hash) if torrent_hash else None


def _download_save_path(torrent_hash: str) -> str | None:
    download_path = str(
        config["qbittorrent"].get("download_path")
        or config["qbittorrent"].get("download_path")
        or ""
    ).strip()
    if not download_path or not torrent_hash:
        return None

    return str(Path(download_path).expanduser().resolve() / torrent_hash)


def _parse_bt_hash(url: str) -> str | None:
    match = re.search(r"xt=urn:btih:([^&]+)", url, flags=re.IGNORECASE)
    return match.group(1) if match else None
