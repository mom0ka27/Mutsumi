import asyncio
import os
from pathlib import Path

from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.auth import get_session, require_admin
from app.core.config import config
from app.models import Anime
from app.schemas import AnimeStorageRead, StorageStatusRead

router = APIRouter(
    prefix="/storage",
    tags=["storage"],
    dependencies=[Depends(require_admin)],
)


@router.get("", response_model=StorageStatusRead)
async def get_storage_status(session: AsyncSession = Depends(get_session)):
    anime = (await session.scalars(select(Anime).order_by(Anime.name_cn, Anime.name))).all()
    return await asyncio.to_thread(_storage_status, anime)


def _storage_status(anime: list[Anime]) -> StorageStatusRead:
    data_path = Path(config["storage"].get("data_path") or "./data")
    data_path = data_path.expanduser().resolve()
    data_path.mkdir(parents=True, exist_ok=True)
    stat = os.statvfs(data_path)
    total = stat.f_blocks * stat.f_frsize
    free = stat.f_bavail * stat.f_frsize
    used = total - (stat.f_bfree * stat.f_frsize)
    data_size, data_file_count = _directory_size(data_path)
    anime_storage = sorted(
        (_anime_storage(item, data_path) for item in anime),
        key=lambda item: item.size_bytes,
        reverse=True,
    )
    return StorageStatusRead(
        data_path=str(data_path),
        data_size_bytes=data_size,
        data_file_count=data_file_count,
        disk_total_bytes=total,
        disk_used_bytes=used,
        disk_free_bytes=free,
        anime=anime_storage,
    )


def _anime_storage(anime: Anime, data_path: Path) -> AnimeStorageRead:
    download_hash = anime.download_hash
    folder_path = data_path / download_hash if download_hash else None
    size_bytes, file_count = (
        _directory_size(folder_path)
        if folder_path is not None and folder_path.is_dir() and not folder_path.is_symlink()
        else (0, 0)
    )
    return AnimeStorageRead(
        anime_id=anime.id,
        name=anime.name_cn or anime.name,
        size_bytes=size_bytes,
        file_count=file_count,
        download_hash=download_hash,
    )


def _directory_size(path: Path) -> tuple[int, int]:
    size_bytes = 0
    file_count = 0
    for root, directories, files in os.walk(path, followlinks=False):
        directories[:] = [
            directory
            for directory in directories
            if not Path(root, directory).is_symlink()
        ]
        for filename in files:
            file_path = Path(root, filename)
            if file_path.is_symlink():
                continue
            try:
                size_bytes += file_path.stat().st_size
                file_count += 1
            except OSError:
                continue
    return size_bytes, file_count
