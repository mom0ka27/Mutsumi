"""Guest accounts must not be able to write to the library."""

import pytest

from app.models import PermissionGroup

ANIME_PAYLOAD = {
    "bangumi_id": 4242,
    "name": "Test Anime",
    "name_cn": "测试",
    "episodes": [{"index": 1, "name": "第一集", "filename": "ep1.mkv"}],
}

METADATA_PAYLOAD = {"name": "Renamed", "name_cn": "改名"}


@pytest.mark.parametrize(
    ("method", "path", "kwargs"),
    [
        ("post", "/api/v1/anime", {"json": ANIME_PAYLOAD}),
        ("put", "/api/v1/anime/1/metadata", {"json": METADATA_PAYLOAD}),
        ("post", "/api/v1/anime/local-folder", {"params": {"bangumi_id": 1}}),
    ],
)
async def test_guest_cannot_write_library(client, auth_headers, method, path, kwargs):
    headers = await auth_headers(PermissionGroup.GUEST)
    response = getattr(client, method)(path, headers=headers, **kwargs)
    assert response.status_code == 403, response.text


async def test_user_can_create_anime(client, auth_headers):
    headers = await auth_headers(PermissionGroup.USER)
    response = client.post("/api/v1/anime", json=ANIME_PAYLOAD, headers=headers)
    assert response.status_code == 201, response.text


async def test_guest_can_read_library(client, auth_headers):
    headers = await auth_headers(PermissionGroup.GUEST)
    assert client.get("/api/v1/anime", headers=headers).status_code == 200


@pytest.mark.parametrize(
    ("method", "path"),
    [
        ("get", "/api/v1/storage"),
        ("get", "/api/v1/users"),
        ("get", "/api/v1/config/qbittorrent"),
    ],
)
async def test_admin_only_routes_reject_plain_users(
    client, auth_headers, method, path
):
    headers = await auth_headers(PermissionGroup.USER)
    assert getattr(client, method)(path, headers=headers).status_code == 403


async def test_only_admin_can_delete_anime(client, auth_headers):
    user_headers = await auth_headers(PermissionGroup.USER)
    created = client.post("/api/v1/anime", json=ANIME_PAYLOAD, headers=user_headers)
    anime_id = created.json()["id"]

    assert (
        client.delete(f"/api/v1/anime/{anime_id}", headers=user_headers).status_code
        == 403
    )

    admin_headers = await auth_headers(PermissionGroup.ADMIN)
    assert (
        client.delete(f"/api/v1/anime/{anime_id}", headers=admin_headers).status_code
        == 204
    )
