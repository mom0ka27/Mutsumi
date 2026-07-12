import asyncio
import hashlib
from pathlib import Path

from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.responses import FileResponse
from sqlalchemy import delete, func, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.core.auth import get_current_user, get_session, require_admin
from app.core.config import config
from app.models import Anime, Episode, User, WatchProgress
from app.schemas import AnimeCreate, AnimeRead, EpisodeRead, WatchProgressRead, WatchProgressUpdate
from app.api.routes.qbittorrent import delete_torrent

router = APIRouter(prefix="/anime", tags=["anime"])


@router.get("", response_model=list[AnimeRead])
async def list_anime(
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
):
    result = await session.scalars(
        select(Anime).options(selectinload(Anime.episodes)).order_by(Anime.id)
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

    anime = Anime(
        bangumi_id=payload.bangumi_id,
        name=payload.name,
        name_cn=payload.name_cn,
        summary=payload.summary,
        image_url=payload.image_url,
        score=payload.score,
        episode_count=payload.episode_count,
        air_date=payload.air_date,
        rank=payload.rank,
        platform=payload.platform,
        tags=payload.tags,
        infobox=[item.model_dump() for item in payload.infobox],
        download_hash=payload.download_hash,
    )
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
    await asyncio.gather(
        *[
            _set_episode_file_hash(anime, episode, episode_read)
            for episode, episode_read in zip(anime.episodes, read.episodes)
        ]
    )
    return read


@router.delete(
    "/{anime_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    dependencies=[Depends(require_admin)],
)
async def delete_anime(
    anime_id: int,
    session: AsyncSession = Depends(get_session),
):
    anime = await session.scalar(
        select(Anime)
        .options(selectinload(Anime.episodes))
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
                detail="Torrent is referenced by another anime",
            )
        await delete_torrent(torrent_hash)

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


@router.get("/{anime_id}/episodes/{episode_id}/video")
async def stream_episode_video(
    anime_id: int,
    episode_id: int,
    _: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
):
    anime = await session.scalar(select(Anime).where(Anime.id == anime_id))
    if not anime:
        raise HTTPException(status_code=404, detail="Anime not found")
    episode = await session.scalar(
        select(Episode).where(Episode.id == episode_id, Episode.anime_id == anime_id)
    )
    if not episode:
        raise HTTPException(status_code=404, detail="Episode not found")

    file_path = _episode_file_path(anime, episode)
    if not file_path or not file_path.is_file():
        raise HTTPException(status_code=404, detail="Video file not found")
    return FileResponse(file_path)


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


def _episode_file_path(anime: Anime, episode: Episode) -> Path | None:
    download_path = str(config["qbittorrent"].get("download_path") or "").strip()
    if not download_path or not anime.download_hash or not episode.filename:
        return None

    root = (Path(download_path).expanduser() / anime.download_hash).resolve()
    path = (root / episode.filename).resolve()
    if root != path and root not in path.parents:
        return None
    return path


async def _set_episode_file_hash(
    anime: Anime,
    episode: Episode,
    episode_read: EpisodeRead,
) -> None:
    file_path = _episode_file_path(anime, episode)
    if not file_path or not file_path.is_file():
        return
    episode_read.file_hash = await asyncio.to_thread(_first_16mb_md5, file_path)


def _first_16mb_md5(file_path: Path) -> str:
    with file_path.open("rb") as file:
        return hashlib.md5(file.read(16 * 1024 * 1024)).hexdigest()
