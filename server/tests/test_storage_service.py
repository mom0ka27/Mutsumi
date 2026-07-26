"""The storage service resolves user-supplied ids and filenames into paths, so
escaping the data directory is the failure mode worth pinning down."""

import pytest
from fastapi import HTTPException

from app.services.storage_service import StorageService, storage_service


@pytest.mark.parametrize(
    "folder_id",
    ["", ".", "..", "../..", "../escape", "a/../..", "/etc"],
)
def test_resource_dir_rejects_escapes(folder_id):
    with pytest.raises(HTTPException) as excinfo:
        storage_service._resource_dir(folder_id)
    assert excinfo.value.status_code == 400


@pytest.mark.parametrize(
    "filename",
    ["../outside.mkv", "../../outside.mkv", "sub/../../outside.mkv"],
)
def test_episode_file_path_rejects_escapes(filename):
    assert storage_service.episode_file_path("abc123", filename) is None


def test_episode_file_path_allows_nested_files(data_path):
    resolved = storage_service.episode_file_path("abc123", "season1/ep1.mkv")
    assert resolved is not None
    assert resolved == (data_path / "abc123" / "season1" / "ep1.mkv")


def test_episode_file_path_requires_both_parts():
    assert storage_service.episode_file_path(None, "ep1.mkv") is None
    assert storage_service.episode_file_path("abc123", None) is None
    assert storage_service.episode_file_path("abc123", "") is None


async def test_create_list_and_delete_local_folder(data_path):
    folder_id = await storage_service.create_local_folder(99)
    folder = data_path / folder_id
    assert folder.is_dir()

    (folder / "ep1.mkv").write_bytes(b"0" * 10)
    (folder / "notes.txt").write_bytes(b"ignored")
    (folder / "nested").mkdir()
    (folder / "nested" / "ep2.mp4").write_bytes(b"0" * 20)

    files = await storage_service.list_local_files(folder_id)
    assert sorted((f.name, f.size) for f in files) == [
        ("ep1.mkv", 10),
        ("nested/ep2.mp4", 20),
    ]

    await storage_service.delete_local_folder(folder_id)
    assert not folder.exists()


async def test_list_local_files_missing_folder_is_404():
    with pytest.raises(HTTPException) as excinfo:
        await storage_service.list_local_files("f" * 32)
    assert excinfo.value.status_code == 404


async def test_status_reports_sizes(data_path):
    folder_id = await storage_service.create_local_folder(1234)
    (data_path / folder_id / "ep1.mkv").write_bytes(b"0" * 2048)

    status = await storage_service.status([(1, "Anime", "动画", folder_id)])
    assert status.data_size_bytes >= 2048
    assert status.anime[0].size_bytes == 2048
    assert status.anime[0].file_count == 1
    assert status.disk_total_bytes > 0

    await storage_service.delete_local_folder(folder_id)


async def test_directory_size_cache_is_reused_then_refreshed(monkeypatch, data_path):
    service = StorageService()
    monkeypatch.setattr(service, "_cache_ttl", lambda: 300)

    folder_id = await service.create_local_folder(555)
    folder = data_path / folder_id
    (folder / "ep1.mkv").write_bytes(b"0" * 1024)

    anime = [(1, "Anime", "动画", folder_id)]
    first = await service.status(anime)
    assert first.anime[0].size_bytes == 1024

    (folder / "ep2.mkv").write_bytes(b"0" * 4096)

    cached = await service.status(anime)
    assert cached.anime[0].size_bytes == 1024, "cached scan should be reused"

    refreshed = await service.status(anime, refresh=True)
    assert refreshed.anime[0].size_bytes == 5120

    await service.delete_local_folder(folder_id)


async def test_route_forwards_the_refresh_flag(client, auth_headers, monkeypatch):
    from app.models import PermissionGroup
    from app.services import storage_service as storage_module

    seen: list[bool] = []
    original = storage_module.storage_service.status

    async def spy(anime, refresh=False):
        seen.append(refresh)
        return await original(anime, refresh=refresh)

    monkeypatch.setattr(storage_module.storage_service, "status", spy)

    headers = await auth_headers(PermissionGroup.ADMIN)
    assert client.get("/api/v1/storage", headers=headers).status_code == 200
    assert (
        client.get("/api/v1/storage?refresh=true", headers=headers).status_code == 200
    )
    assert seen == [False, True]


async def test_delete_invalidates_the_cache(monkeypatch, data_path):
    service = StorageService()
    monkeypatch.setattr(service, "_cache_ttl", lambda: 300)

    folder_id = await service.create_local_folder(777)
    (data_path / folder_id / "ep1.mkv").write_bytes(b"0" * 1024)
    anime = [(1, "Anime", "动画", folder_id)]
    assert (await service.status(anime)).anime[0].size_bytes == 1024

    await service.delete_local_folder(folder_id)
    assert (await service.status(anime)).anime[0].size_bytes == 0
