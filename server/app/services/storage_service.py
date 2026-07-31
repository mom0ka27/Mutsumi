import asyncio
import hashlib
import os
import shutil
import threading
import time
from pathlib import Path

from fastapi import HTTPException

from app.core.config import config
from app.models import Anime
from app.schemas import AnimeStorageRead, QBittorrentFileRead, StorageStatusRead

VIDEO_EXTENSIONS = {".mkv", ".mp4", ".avi", ".mov", ".webm"}

DEFAULT_STATUS_CACHE_SECONDS = 60


class _DirectorySizeCache:
    """TTL cache for directory walks.

    Scanning the whole data directory costs one ``stat`` per file, so a storage
    page refresh used to re-walk everything. Entries are keyed by resolved path
    and shared between the root scan and the per-anime scans.
    """

    def __init__(self) -> None:
        self._entries: dict[str, tuple[float, tuple[int, int]]] = {}
        self._lock = threading.Lock()

    def get(self, path: Path, ttl: float) -> tuple[int, int] | None:
        if ttl <= 0:
            return None
        with self._lock:
            entry = self._entries.get(str(path))
        if entry is None:
            return None
        stored_at, value = entry
        if time.monotonic() - stored_at > ttl:
            return None
        return value

    def set(self, path: Path, value: tuple[int, int]) -> None:
        with self._lock:
            self._entries[str(path)] = (time.monotonic(), value)

    def clear(self) -> None:
        with self._lock:
            self._entries.clear()


class StorageService:
    def __init__(self) -> None:
        self._cache = _DirectorySizeCache()
        self._status_lock = asyncio.Lock()

    async def status(
        self,
        anime: list[Anime],
        refresh: bool = False,
    ) -> StorageStatusRead:
        # Serialised so concurrent requests share one walk instead of racing
        # through the whole data directory in parallel.
        async with self._status_lock:
            if refresh:
                self._cache.clear()
            return await asyncio.to_thread(self._status, anime)

    async def create_local_folder(self, bangumi_id: int) -> str:
        folder_id = hashlib.md5(str(bangumi_id).encode()).hexdigest()
        folder_path = self._resource_dir(folder_id)
        await asyncio.to_thread(folder_path.mkdir, parents=True, exist_ok=True)
        return folder_id

    async def list_local_files(self, folder_id: str) -> list[QBittorrentFileRead]:
        folder_path = self._resource_dir(folder_id)
        return await asyncio.to_thread(self._list_local_files, folder_path)

    async def delete_local_folder(self, folder_id: str) -> None:
        folder_path = self._resource_dir(folder_id)
        await asyncio.to_thread(self._delete_local_folder, folder_path)
        self._cache.clear()

    async def list_sibling_files(self, path: Path) -> list[Path]:
        """Files next to ``path``, sorted by name."""
        return await asyncio.to_thread(self._list_sibling_files, path)

    async def is_file(self, path: Path | None) -> bool:
        if path is None:
            return False
        return await asyncio.to_thread(path.is_file)

    def episode_file_path(
        self,
        download_hash: str | None,
        filename: str | None,
    ) -> Path | None:
        if not download_hash or not filename:
            return None
        root = self._resource_dir(download_hash)
        path = (root / filename).resolve()
        return path if root in path.parents else None

    def _status(self, anime: list[Anime]) -> StorageStatusRead:
        data_path = self._root(create=True)
        stat = os.statvfs(data_path)
        total = stat.f_blocks * stat.f_frsize
        free = stat.f_bavail * stat.f_frsize
        used = total - (stat.f_bfree * stat.f_frsize)
        data_size, data_file_count = self._directory_size(data_path)
        counted_files: set[str] = set()
        anime_storage = sorted(
            (
                self._anime_storage(item, counted_files)
                for item in anime
            ),
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

    def _list_local_files(self, folder_path: Path) -> list[QBittorrentFileRead]:
        if not folder_path.is_dir():
            raise HTTPException(status_code=404, detail="Folder not found")
        return [
            QBittorrentFileRead(
                name=str(entry.relative_to(folder_path)),
                size=entry.stat().st_size,
            )
            for entry in sorted(folder_path.rglob("*"))
            if entry.is_file() and entry.suffix.lower() in VIDEO_EXTENSIONS
        ]

    def _delete_local_folder(self, folder_path: Path) -> None:
        if folder_path.is_dir():
            shutil.rmtree(folder_path)

    def _list_sibling_files(self, path: Path) -> list[Path]:
        parent = path.parent
        if not parent.is_dir():
            return []
        return [entry for entry in sorted(parent.iterdir()) if entry.is_file()]

    def _root(self, create: bool = False) -> Path:
        data_path = str(config["storage"].get("data_path") or "").strip()
        if not data_path:
            raise HTTPException(status_code=500, detail="Data path not configured")
        root = Path(data_path).expanduser().resolve()
        if create:
            root.mkdir(parents=True, exist_ok=True)
        return root

    def _resource_dir(self, resource_id: str) -> Path:
        root = self._root()
        path = (root / resource_id).resolve()
        if path == root or root not in path.parents:
            raise HTTPException(status_code=400, detail="Invalid folder id")
        return path

    def _anime_storage(
        self,
        anime: Anime,
        counted_files: set[str],
    ) -> AnimeStorageRead:
        size_bytes = 0
        file_count = 0
        download_hash = anime.download_hash
        for episode in anime.episodes:
            path = self.episode_file_path(
                episode.download_hash or download_hash,
                episode.filename,
            )
            if path is None or path.is_symlink() or not path.is_file():
                continue
            file_key = str(path)
            if file_key in counted_files:
                continue
            try:
                size_bytes += path.stat().st_size
            except OSError:
                continue
            counted_files.add(file_key)
            file_count += 1
        return AnimeStorageRead(
            anime_id=anime.id,
            name=anime.name_cn or anime.name,
            size_bytes=size_bytes,
            file_count=file_count,
            download_hash=download_hash,
        )

    def _directory_size(self, path: Path) -> tuple[int, int]:
        ttl = self._cache_ttl()
        cached = self._cache.get(path, ttl)
        if cached is not None:
            return cached

        size_bytes = 0
        file_count = 0
        for root, directories, files in os.walk(path, followlinks=False):
            directories[:] = [directory for directory in directories if not Path(root, directory).is_symlink()]
            for filename in files:
                file_path = Path(root, filename)
                if file_path.is_symlink():
                    continue
                try:
                    size_bytes += file_path.stat().st_size
                    file_count += 1
                except OSError:
                    continue

        result = (size_bytes, file_count)
        if ttl > 0:
            self._cache.set(path, result)
        return result

    def _cache_ttl(self) -> float:
        try:
            return float(
                config["storage"].get(
                    "status_cache_seconds", DEFAULT_STATUS_CACHE_SECONDS
                )
            )
        except (TypeError, ValueError):
            return DEFAULT_STATUS_CACHE_SECONDS


storage_service = StorageService()
