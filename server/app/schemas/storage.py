from pydantic import BaseModel


class AnimeStorageRead(BaseModel):
    anime_id: int
    name: str
    size_bytes: int
    file_count: int
    download_hash: str | None


class StorageStatusRead(BaseModel):
    data_path: str
    data_size_bytes: int
    data_file_count: int
    disk_total_bytes: int
    disk_used_bytes: int
    disk_free_bytes: int
    anime: list[AnimeStorageRead]
