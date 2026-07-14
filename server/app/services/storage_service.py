import os
import shutil
from pathlib import Path

from fastapi import HTTPException

from app.core.config import config
from app.schemas import AnimeStorageRead, QBittorrentFileRead, StorageStatusRead

VIDEO_EXTENSIONS = {".mkv", ".mp4", ".avi", ".mov", ".webm"}


class StorageService:
    def status(self, anime: list[tuple[int, str, str, str]]) -> StorageStatusRead:
        data_path = self._root(create=True)
        stat = os.statvfs(data_path)
        total = stat.f_blocks * stat.f_frsize
        free = stat.f_bavail * stat.f_frsize
        used = total - (stat.f_bfree * stat.f_frsize)
        data_size, data_file_count = self._directory_size(data_path)
        anime_storage = sorted(
            (self._anime_storage(item, data_path) for item in anime),
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

    def create_local_folder(self, bangumi_id: int) -> str:
        import hashlib

        folder_id = hashlib.md5(str(bangumi_id).encode()).hexdigest()
        self._resource_dir(folder_id).mkdir(parents=True, exist_ok=True)
        return folder_id

    def list_local_files(self, folder_id: str) -> list[QBittorrentFileRead]:
        folder_path = self._resource_dir(folder_id)
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

    def episode_file_path(self, download_hash: str | None, filename: str | None) -> Path | None:
        if not download_hash or not filename:
            return None
        root = self._resource_dir(download_hash)
        path = (root / filename).resolve()
        return path if root == path or root in path.parents else None

    def delete_local_folder(self, folder_id: str) -> None:
        folder_path = self._resource_dir(folder_id)
        if folder_path.is_dir():
            shutil.rmtree(folder_path)

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
        if root not in path.parents:
            raise HTTPException(status_code=400, detail="Invalid folder id")
        return path

    def _anime_storage(self, anime: tuple[int, str, str, str], data_path: Path) -> AnimeStorageRead:
        download_hash = anime[3]
        folder_path = (data_path / download_hash).resolve() if download_hash else None
        size_bytes, file_count = (
            self._directory_size(folder_path)
            if folder_path is not None and data_path in folder_path.parents and folder_path.is_dir() and not folder_path.is_symlink()
            else (0, 0)
        )
        return AnimeStorageRead(
            anime_id=anime[0],
            name=anime[2] or anime[1],
            size_bytes=size_bytes,
            file_count=file_count,
            download_hash=download_hash,
        )

    def _directory_size(self, path: Path) -> tuple[int, int]:
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
        return size_bytes, file_count


storage_service = StorageService()
