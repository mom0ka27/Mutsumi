import asyncio

import httpx

from app.core.config import config
from app.core.qbittorrent_error import QBittorrentError

_cookies = httpx.Cookies()
_cookie_lock = asyncio.Lock()


async def delete_torrent(torrent_hash: str, delete_files: bool = True) -> None:
    client = await _client()
    try:
        response = await _post(
            client,
            "/api/v2/torrents/delete",
            data={"hashes": torrent_hash, "deleteFiles": "true" if delete_files else "false"},
        )
        if response.status_code >= 400 or response.text.strip() == "Fails.":
            raise QBittorrentError(21008, "删除下载任务或文件失败")
    finally:
        await client.aclose()


async def _client() -> httpx.AsyncClient:
    qbittorrent_config = config["qbittorrent"]
    url = (qbittorrent_config.get("url") or "").rstrip("/")
    if not url:
        raise QBittorrentError(21001, "qBittorrent 尚未配置")
    async with _cookie_lock:
        cookies = httpx.Cookies(_cookies)
    client = httpx.AsyncClient(base_url=url, timeout=10, cookies=cookies)
    try:
        if client.cookies.get("SID") is None:
            await _login(client)
        return client
    except Exception:
        await client.aclose()
        raise


async def _post(client: httpx.AsyncClient, url: str, data: dict[str, str]) -> httpx.Response:
    response = await client.post(url, data=data)
    await _save_cookies(client)
    if response.status_code not in (401, 403):
        return response
    async with _cookie_lock:
        global _cookies
        _cookies = httpx.Cookies()
    await _login(client)
    response = await client.post(url, data=data)
    await _save_cookies(client)
    return response


async def _login(client: httpx.AsyncClient) -> None:
    qbittorrent_config = config["qbittorrent"]
    response = await client.post(
        "/api/v2/auth/login",
        data={
            "username": qbittorrent_config.get("username") or "",
            "password": qbittorrent_config.get("password") or "",
        },
    )
    await _save_cookies(client)
    if response.status_code >= 400 or response.text.strip() == "Fails.":
        raise QBittorrentError(21003, f"qBittorrent 登录失败: {response.text.strip()}")


async def _save_cookies(client: httpx.AsyncClient) -> None:
    async with _cookie_lock:
        _cookies.update(client.cookies)
