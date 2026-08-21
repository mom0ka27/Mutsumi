from fastapi import APIRouter, Depends, Query
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.core.auth import get_session, require_admin
from app.models import Anime
from app.models.anime import anime_has_content
from app.schemas import StorageStatusRead
from app.services.storage_service import storage_service

router = APIRouter(
    prefix="/storage",
    tags=["storage"],
    dependencies=[Depends(require_admin)],
)


@router.get("", response_model=StorageStatusRead)
async def get_storage_status(
    session: AsyncSession = Depends(get_session),
    refresh: bool = Query(
        default=False,
        description="Bypass the directory size cache and rescan.",
    ),
):
    anime = list(
        (
            await session.scalars(
                select(Anime)
                .options(selectinload(Anime.episodes))
                # Placeholders from subscriptions own no files; they would show
                # up as zero-byte rows.
                .where(anime_has_content())
                .order_by(Anime.name_cn, Anime.name)
            )
        ).all()
    )
    return await storage_service.status(anime, refresh=refresh)
