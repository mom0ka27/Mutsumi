import asyncio
import hashlib
import logging
from pathlib import Path

from fastapi import APIRouter, Depends, HTTPException, Query, status
from fastapi.responses import FileResponse
from sqlalchemy import delete, func, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.core.auth import get_current_user, get_session, require_admin
from app.models import Anime, Episode, User, WatchProgress
from app.schemas import (
    AnimeCreate,
    AnimeMetadataUpdate,
    AnimeRead,
    EpisodeRead,
    WatchProgressRead,
    WatchProgressUpdate,
)
from app.services.qbittorrent_service import delete_torrent
from app.services.storage_service import storage_service

SUBTITLE_EXTENSIONS = {".ass", ".ssa", ".srt", ".vtt"}

router = APIRouter(prefix="/anime", tags=["anime"])
logger = logging.getLogger(__name__)

@router.get("", response_model=list[AnimeRead])
async def list_anime(
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
    skip: int = Query(default=0, ge=0),
    limit: int = Query(default=100, ge=1, le=1000),
):
    result = await session.scalars(
        select(Anime)
        .options(selectinload(Anime.episodes))
        .order_by(Anime.id)
        .offset(skip)
        .limit(limit)
    )
    return await _with_watch_progress(list(result), current_user.id, session)


@router.post("", response_model=AnimeRead, status_code=status.HTTP_201_CREATED)
async def create_anime(
    payload: AnimeCreate,
    _: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
):
    exists = await session.scalar(
        select(Anime).where(Anime.bangumi_id == payload.bangumi_id)
    )
    if exists:
        raise HTTPException(status_code=409, detail="Anime already exists")

    anime = Anime(bangumi_id=payload.bangumi_id, download_hash=payload.download_hash)
    _apply_metadata(anime, payload)
    anime.episodes = [
        Episode(index=episode.index, name=episode.name, filename=episode.filename)
        for episode in payload.episodes or []
    ]

    session.add(anime)
    await session.commit()

    created = await session.scalar(
        select(Anime)
        .options(selectinload(Anime.episodes))
        .where(Anime.id == anime.id)
    )
    return created


@router.put("/{anime_id}/metadata", response_model=AnimeRead)
async def update_anime_metadata(
    anime_id: int,
    payload: AnimeMetadataUpdate,
    _: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
):
    anime = await session.scalar(
        select(Anime)
        .options(selectinload(Anime.episodes))
        .where(Anime.id == anime_id)
    )
    if not anime:
        raise HTTPException(status_code=404, detail="Anime not found")

    _apply_metadata(anime, payload)
    await session.commit()
    await session.refresh(anime)
    return (await _with_watch_progress([anime], _.id, session))[0]


@router.get("/{anime_id}", response_model=AnimeRead)
async def get_anime(
    anime_id: int,
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
):
    anime = await session.scalar(
        select(Anime)
        .options(selectinload(Anime.episodes))
        .where(Anime.id == anime_id)
    )
    if not anime:
        raise HTTPException(status_code=404, detail="Anime not found")
    read = (await _with_watch_progress([anime], current_user.id, session))[0]
    return read


@router.delete(
    "/{anime_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    dependencies=[Depends(require_admin)],
)
async def delete_anime(
    anime_id: int,
    delete_files: bool = Query(default=True),
    session: AsyncSession = Depends(get_session),
):
    anime = await session.scalar(
        select(Anime)
        .where(Anime.id == anime_id)
    )
    if not anime:
        raise HTTPException(status_code=404, detail="Anime not found")

    torrent_hash = (anime.download_hash or "").strip()
    if torrent_hash:
        references = await session.scalar(
            select(func.count())
            .select_from(Anime)
            .where(Anime.download_hash == torrent_hash, Anime.id != anime_id)
        )
        if references:
            raise HTTPException(
                status_code=409,
                detail="Resource is referenced by another anime",
            )
        if _is_bt_hash(torrent_hash):
            await delete_torrent(torrent_hash, delete_files=delete_files)
        elif delete_files:
            storage_service.delete_local_folder(torrent_hash)

    await session.execute(
        delete(WatchProgress).where(WatchProgress.anime_id == anime_id)
    )
    await session.delete(anime)
    await session.commit()


@router.put("/{anime_id}/progress", response_model=WatchProgressRead)
async def update_watch_progress(
    anime_id: int,
    payload: WatchProgressUpdate,
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
):
    anime = await session.scalar(select(Anime).where(Anime.id == anime_id))
    if not anime:
        raise HTTPException(status_code=404, detail="Anime not found")

    if payload.episode_id is not None:
        episode = await session.scalar(
            select(Episode).where(
                Episode.id == payload.episode_id,
                Episode.anime_id == anime_id,
            )
        )
        if not episode:
            raise HTTPException(status_code=404, detail="Episode not found")

    progress = await session.scalar(
        select(WatchProgress).where(
            WatchProgress.user_id == current_user.id,
            WatchProgress.anime_id == anime_id,
        )
    )
    if not progress:
        progress = WatchProgress(user_id=current_user.id, anime_id=anime_id)
        session.add(progress)

    progress.episode_id = payload.episode_id
    progress.position_seconds = max(payload.position_seconds, 0)
    await session.commit()
    return WatchProgressRead(
        episode_id=progress.episode_id,
        position_seconds=progress.position_seconds,
    )


@router.head("/{anime_id}/episodes/{episode_id}/video")
@router.get("/{anime_id}/episodes/{episode_id}/video")
async def stream_episode_video(
    anime_id: int,
    episode_id: int,
    _: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
):
    anime, episode = await _get_episode(anime_id, episode_id, session)

    file_path = _episode_file_path(anime, episode)
    logger.info(f"Streaming video from {file_path}")
    if not file_path or not file_path.is_file():
        raise HTTPException(status_code=404, detail="Video file not found")
    return FileResponse(file_path)


@router.get("/{anime_id}/episodes/{episode_id}/subtitles")
async def list_episode_subtitles(
    anime_id: int,
    episode_id: int,
    _: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
):
    anime, episode = await _get_episode(anime_id, episode_id, session)
    video_path = _episode_file_path(anime, episode)
    if not video_path or not video_path.is_file():
        raise HTTPException(status_code=404, detail="Video file not found")

    subtitles = []
    for path in sorted(video_path.parent.iterdir()):
        if not _is_episode_subtitle(path, video_path):
            continue
        subtitles.append(
            {
                "filename": str(path.relative_to(video_path.parent)),
                "name": _subtitle_display_name(path, video_path),
            }
        )
    return subtitles


@router.get("/{anime_id}/episodes/{episode_id}/subtitles/file")
async def get_episode_subtitle(
    anime_id: int,
    episode_id: int,
    filename: str = Query(...),
    _: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
):
    anime, episode = await _get_episode(anime_id, episode_id, session)
    video_path = _episode_file_path(anime, episode)
    if not video_path or not video_path.is_file():
        raise HTTPException(status_code=404, detail="Video file not found")
    subtitle_path = storage_service.episode_file_path(
        anime.download_hash,
        str(Path(episode.filename).parent / filename),
    )
    if (
        not subtitle_path
        or not subtitle_path.is_file()
        or subtitle_path.parent != video_path.parent
        or not _is_episode_subtitle(subtitle_path, video_path)
    ):
        raise HTTPException(status_code=404, detail="Subtitle file not found")
    return FileResponse(subtitle_path)


@router.get("/{anime_id}/episodes/{episode_id}/file-hash")
async def get_episode_file_hash(
    anime_id: int,
    episode_id: int,
    _: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
):
    anime, episode = await _get_episode(anime_id, episode_id, session)

    if episode.file_hash:
        return {"file_hash": episode.file_hash}

    file_path = _episode_file_path(anime, episode)
    if not file_path or not file_path.is_file():
        raise HTTPException(status_code=404, detail="Video file not found")

    file_hash = await asyncio.to_thread(_first_16mb_md5, file_path)
    if not file_hash:
        raise HTTPException(status_code=500, detail="Failed to compute file hash")
    episode.file_hash = file_hash
    await session.commit()
    return {"file_hash": file_hash}


async def _get_episode(
    anime_id: int,
    episode_id: int,
    session: AsyncSession,
) -> tuple[Anime, Episode]:
    anime = await session.scalar(select(Anime).where(Anime.id == anime_id))
    if not anime:
        raise HTTPException(status_code=404, detail="Anime not found")
    episode = await session.scalar(
        select(Episode).where(Episode.id == episode_id, Episode.anime_id == anime_id)
    )
    if not episode:
        raise HTTPException(status_code=404, detail="Episode not found")
    return anime, episode


@router.post("/local-folder")
async def create_local_folder(
    bangumi_id: int = Query(...),
    _: User = Depends(get_current_user),
):
    try:
        folder_id = storage_service.create_local_folder(bangumi_id)
    except OSError as e:
        raise HTTPException(status_code=500, detail=f"Failed to create folder: {e}")
    return {"folder_id": folder_id}


@router.get("/local-folder/{folder_id}/files")
async def list_local_folder_files(
    folder_id: str,
    _: User = Depends(get_current_user),
):
    return [file.model_dump() for file in storage_service.list_local_files(folder_id)]


async def _with_watch_progress(
    animes: list[Anime],
    user_id: int,
    session: AsyncSession,
) -> list[AnimeRead]:
    if not animes:
        return []

    anime_ids = [anime.id for anime in animes]
    progress_result = await session.scalars(
        select(WatchProgress).where(
            WatchProgress.user_id == user_id,
            WatchProgress.anime_id.in_(anime_ids),
        )
    )
    progress_by_anime_id = {progress.anime_id: progress for progress in progress_result}

    reads = []
    for anime in animes:
        read = AnimeRead.model_validate(anime)
        progress = progress_by_anime_id.get(anime.id)
        if progress:
            read.watch_progress = WatchProgressRead(
                episode_id=progress.episode_id,
                position_seconds=progress.position_seconds,
            )
        reads.append(read)
    return reads


def _episode_file_path(anime: Anime, episode: Episode):
    return storage_service.episode_file_path(anime.download_hash, episode.filename)


def _apply_metadata(anime: Anime, payload: AnimeCreate | AnimeMetadataUpdate) -> None:
    anime.name = payload.name
    anime.name_cn = payload.name_cn
    anime.summary = payload.summary
    anime.image_url = payload.image_url
    anime.score = payload.score
    anime.episode_count = payload.episode_count
    anime.air_date = payload.air_date
    anime.rank = payload.rank
    anime.platform = payload.platform
    anime.tags = payload.tags
    anime.infobox = [item.model_dump() for item in payload.infobox]


def _is_episode_subtitle(path: Path, video_path: Path) -> bool:
    return (
        path.is_file()
        and path.suffix.lower() in SUBTITLE_EXTENSIONS
        and video_path.stem in path.name
    )


def _subtitle_display_name(path: Path, video_path: Path) -> str:
    remaining = path.name.replace(video_path.stem, "", 1)
    remaining = remaining.removesuffix(path.suffix)
    remaining = remaining.strip(" .-_()[]")
    return remaining or "默认字幕"


def _first_16mb_md5(file_path: Path) -> str | None:
    with file_path.open("rb") as file:
        if file_path.stat().st_size < 16 * 1024 * 1024:
            return None
        return hashlib.md5(file.read(16 * 1024 * 1024)).hexdigest()


def _is_bt_hash(hash_str: str) -> bool:
    return len(hash_str) == 40 and all(c in "0123456789abcdef" for c in hash_str.lower())
