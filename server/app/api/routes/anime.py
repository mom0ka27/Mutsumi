import asyncio
import hashlib
import logging
from pathlib import Path

from fastapi import APIRouter, Depends, HTTPException, Query, status
from fastapi.responses import FileResponse
from sqlalchemy import delete, func, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.core.auth import (
    get_current_user,
    get_session,
    require_admin,
    require_download_permission,
)
from app.models import Anime, Episode, Series, User, WatchProgress
from app.models.anime import anime_has_content
from app.schemas import (
    AnimeCreate,
    EpisodeDownloadCreate,
    AnimeMetadataUpdate,
    AnimeRead,
    AnimeSummaryRead,
    EpisodeRead,
    SeriesCreate,
    SeriesRead,
    WatchProgressRead,
    WatchProgressUpdate,
)
from app.services.qbittorrent_service import delete_torrent
from app.api.routes.qbittorrent import sync_torrent_file_priorities
from app.services.storage_service import storage_service

SUBTITLE_EXTENSIONS = {".ass", ".ssa", ".srt", ".vtt"}

router = APIRouter(prefix="/anime", tags=["anime"])
logger = logging.getLogger(__name__)


@router.get("/series", response_model=list[SeriesRead])
async def list_series(
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
):
    result = await session.scalars(
        select(Series)
        .options(selectinload(Series.animes).selectinload(Anime.episodes))
        .order_by(Series.id)
    )
    series_list = list(result)
    reads = []
    for series in series_list:
        animes = await _with_watch_progress(
            list(series.animes), current_user.id, session, AnimeSummaryRead
        )
        reads.append(SeriesRead(id=series.id, name=series.name, animes=animes))
    return reads


@router.post("/series", response_model=SeriesRead, status_code=status.HTTP_201_CREATED)
async def create_series(
    payload: SeriesCreate,
    current_user: User = Depends(require_download_permission),
    session: AsyncSession = Depends(get_session),
):
    anime_ids = list(dict.fromkeys(payload.anime_ids))
    animes = list(
        await session.scalars(
            select(Anime)
            .options(selectinload(Anime.episodes))
            .where(Anime.id.in_(anime_ids))
            .order_by(Anime.id)
        )
    )
    if len(animes) != len(anime_ids):
        raise HTTPException(status_code=404, detail="Anime not found")
    if any(anime.series_id is not None for anime in animes):
        raise HTTPException(status_code=409, detail="Anime already belongs to a series")
    series = Series(name=payload.name.strip(), animes=animes)
    session.add(series)
    await session.commit()
    reads = await _with_watch_progress(
        animes, current_user.id, session, AnimeSummaryRead
    )
    return SeriesRead(id=series.id, name=series.name, animes=reads)

@router.get("", response_model=list[AnimeSummaryRead])
async def list_anime(
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
    skip: int = Query(default=0, ge=0),
    limit: int = Query(default=100, ge=1, le=1000),
):
    result = await session.scalars(
        select(Anime)
        .options(selectinload(Anime.episodes))
        .where(anime_has_content())
        .order_by(Anime.id)
        .offset(skip)
        .limit(limit)
    )
    return await _with_watch_progress(
        list(result), current_user.id, session, AnimeSummaryRead
    )


@router.post("", response_model=AnimeRead, status_code=status.HTTP_201_CREATED)
async def create_anime(
    payload: AnimeCreate,
    _: User = Depends(require_download_permission),
    session: AsyncSession = Depends(get_session),
):
    # Merge instead of rejecting duplicates. A subscription creates the Anime
    # row before any file exists, so a later manual download of the same show
    # arrives here with the row already present -- and a 409 would abort a
    # download that is perfectly valid.
    anime = await session.scalar(
        select(Anime)
        .options(selectinload(Anime.episodes))
        .where(Anime.bangumi_id == payload.bangumi_id)
    )
    if anime is None:
        anime = Anime(bangumi_id=payload.bangumi_id, download_hash=payload.download_hash)
        _apply_metadata(anime, payload)
        anime.episodes = [
            Episode(index=episode.index, name=episode.name, filename=episode.filename)
            for episode in payload.episodes or []
        ]
        session.add(anime)
    else:
        _apply_metadata(anime, payload)
        # Never overwrite an existing torrent: episodes carry their own hash,
        # and the anime-level one is the fallback for the first import.
        anime.download_hash = anime.download_hash or payload.download_hash
        by_index = {episode.index: episode for episode in anime.episodes}
        for payload_episode in payload.episodes or []:
            # These episodes come from this payload's torrent, which may differ
            # from the anime-level hash, so pin it per episode as
            # ``add_downloaded_episodes`` does.
            episode = by_index.get(payload_episode.index)
            if episode is None:
                anime.episodes.append(
                    Episode(
                        index=payload_episode.index,
                        name=payload_episode.name,
                        filename=payload_episode.filename,
                        download_hash=payload.download_hash,
                    )
                )
            else:
                episode.name = payload_episode.name
                episode.filename = payload_episode.filename
                episode.download_hash = payload.download_hash
                episode.file_hash = None

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
    current_user: User = Depends(require_download_permission),
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
    return (await _with_watch_progress([anime], current_user.id, session))[0]


@router.post("/{anime_id}/episodes", response_model=AnimeRead)
async def add_downloaded_episodes(
    anime_id: int,
    payload: EpisodeDownloadCreate,
    current_user: User = Depends(require_download_permission),
    session: AsyncSession = Depends(get_session),
):
    anime = await session.scalar(
        select(Anime)
        .options(selectinload(Anime.episodes))
        .where(Anime.id == anime_id)
    )
    if not anime:
        raise HTTPException(status_code=404, detail="Anime not found")

    by_index = {episode.index: episode for episode in anime.episodes}
    for payload_episode in payload.episodes:
        episode = by_index.get(payload_episode.index)
        if episode is None:
            anime.episodes.append(
                Episode(
                    index=payload_episode.index,
                    name=payload_episode.name,
                    filename=payload_episode.filename,
                    download_hash=payload.download_hash,
                )
            )
        else:
            episode.name = payload_episode.name
            episode.filename = payload_episode.filename
            episode.download_hash = payload.download_hash
            episode.file_hash = None

    hash_to_filenames: dict[str, set[str]] = {}
    for episode in anime.episodes:
        download_hash = episode.download_hash or anime.download_hash
        if download_hash and episode.filename and len(download_hash) == 40:
            hash_to_filenames.setdefault(download_hash, set()).add(episode.filename)

    if hash_to_filenames:
        shared_animes = list(
            (
                await session.scalars(
                    select(Anime)
                    .options(selectinload(Anime.episodes))
                    .where(
                        (Anime.download_hash.in_(hash_to_filenames))
                        | Anime.episodes.any(
                            Episode.download_hash.in_(hash_to_filenames)
                        )
                    )
                )
            ).all()
        )
        for shared_anime in shared_animes:
            for episode in shared_anime.episodes:
                download_hash = episode.download_hash or shared_anime.download_hash
                if (
                    download_hash in hash_to_filenames
                    and episode.filename
                ):
                    hash_to_filenames[download_hash].add(episode.filename)

    for download_hash, filenames in hash_to_filenames.items():
        await sync_torrent_file_priorities(download_hash, filenames)

    await session.commit()
    await session.refresh(anime)
    return (await _with_watch_progress([anime], current_user.id, session))[0]


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
            await storage_service.delete_local_folder(torrent_hash)

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
    logger.info("Streaming video from %s", file_path)
    if not await storage_service.is_file(file_path):
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
    if not await storage_service.is_file(video_path):
        raise HTTPException(status_code=404, detail="Video file not found")

    siblings = await storage_service.list_sibling_files(video_path)
    return [
        {
            "filename": str(path.relative_to(video_path.parent)),
            "name": _subtitle_display_name(path, video_path),
        }
        for path in siblings
        if _is_episode_subtitle(path, video_path)
    ]


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
    if not await storage_service.is_file(video_path):
        raise HTTPException(status_code=404, detail="Video file not found")
    subtitle_path = storage_service.episode_file_path(
        anime.download_hash,
        str(Path(episode.filename).parent / filename),
    )
    if (
        subtitle_path is None
        or subtitle_path.parent != video_path.parent
        or not _is_episode_subtitle(subtitle_path, video_path)
        or not await storage_service.is_file(subtitle_path)
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
    if not await storage_service.is_file(file_path):
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
    _: User = Depends(require_download_permission),
):
    try:
        folder_id = await storage_service.create_local_folder(bangumi_id)
    except OSError as e:
        raise HTTPException(status_code=500, detail=f"Failed to create folder: {e}")
    return {"folder_id": folder_id}


@router.get("/local-folder/{folder_id}/files")
async def list_local_folder_files(
    folder_id: str,
    _: User = Depends(get_current_user),
):
    files = await storage_service.list_local_files(folder_id)
    return [file.model_dump() for file in files]


async def _with_watch_progress(
    animes: list[Anime],
    user_id: int,
    session: AsyncSession,
    model: type[AnimeRead] | type[AnimeSummaryRead] = AnimeRead,
) -> list[AnimeRead | AnimeSummaryRead]:
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
        read = model.model_validate(anime)
        progress = progress_by_anime_id.get(anime.id)
        if progress:
            read.watch_progress = WatchProgressRead(
                episode_id=progress.episode_id,
                position_seconds=progress.position_seconds,
            )
        reads.append(read)
    return reads


def _episode_file_path(anime: Anime, episode: Episode):
    return storage_service.episode_file_path(
        episode.download_hash or anime.download_hash,
        episode.filename,
    )


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
    anime.media_type = payload.media_type
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
