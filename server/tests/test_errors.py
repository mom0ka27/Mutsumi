"""Business errors must arrive as HTTP status codes, not as 200 + a code field."""

from http import HTTPStatus

from app.core.qbittorrent_error import QBittorrentError
from app.models import PermissionGroup


def test_default_status_is_bad_gateway():
    error = QBittorrentError(21004, "boom")
    assert error.status_code == HTTPStatus.BAD_GATEWAY
    assert error.msg == "boom"


async def test_unconfigured_qbittorrent_returns_503(client, auth_headers):
    headers = await auth_headers(PermissionGroup.ADMIN)
    response = client.get("/api/v1/qbittorrent/torrents", headers=headers)
    assert response.status_code == 503
    assert response.json() == {"detail": "qBittorrent 尚未配置", "code": 21001}


async def test_client_side_error_returns_400(client, auth_headers):
    headers = await auth_headers(PermissionGroup.ADMIN)
    response = client.post(
        "/api/v1/qbittorrent/torrents/download",
        headers=headers,
        json={"source": "magnet:?xt=urn:btih:abc", "filenames": []},
    )
    assert response.status_code == 400
    assert response.json()["code"] == 21010


async def test_missing_anime_is_404(client, auth_headers):
    headers = await auth_headers(PermissionGroup.ADMIN)
    assert client.get("/api/v1/anime/999999", headers=headers).status_code == 404
    assert (
        client.put(
            "/api/v1/anime/999999/metadata", headers=headers, json={"name": "x"}
        ).status_code
        == 404
    )


def test_http_errors_keep_the_detail_shape(client):
    response = client.get("/api/v1/anime")
    assert response.status_code == 401
    assert "detail" in response.json()
