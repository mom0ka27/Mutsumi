import asyncio
from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.auth import get_session, require_admin
from app.models import Anime
from app.schemas import StorageStatusRead
from app.services.storage_service import storage_service

router = APIRouter(
    prefix="/storage",
    tags=["storage"],
    dependencies=[Depends(require_admin)],
)


@router.get("", response_model=StorageStatusRead)
async def get_storage_status(session: AsyncSession = Depends(get_session)):
    anime = (await session.execute(select(Anime.id, Anime.name, Anime.name_cn, Anime.download_hash).order_by(Anime.name_cn, Anime.name))).all()
    return await asyncio.to_thread(storage_service.status, anime)
