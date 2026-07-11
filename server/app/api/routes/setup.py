from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.auth import create_access_token, get_password_hash, get_session
from app.core.config import config, save_config
from app.models import PermissionGroup, User
from app.schemas import SetupCreate, SetupStatus, Token

router = APIRouter(prefix="/setup", tags=["setup"])


@router.get("", response_model=SetupStatus)
async def get_setup_status(session: AsyncSession = Depends(get_session)):
    total_users = await session.scalar(select(func.count()).select_from(User))
    return SetupStatus(
        initialized=bool(total_users),
        server_name=config["server"]["name"],
    )


@router.post("", response_model=Token, status_code=status.HTTP_201_CREATED)
async def initialize_server(
    payload: SetupCreate,
    session: AsyncSession = Depends(get_session),
):
    total_users = await session.scalar(select(func.count()).select_from(User))
    if total_users:
        raise HTTPException(status_code=409, detail="Server already initialized")

    if payload.server_name is not None and payload.server_name.strip():
        config["server"]["name"] = payload.server_name.strip()
        save_config(config)

    user = User(
        username=payload.username,
        password_hash=get_password_hash(payload.password),
        permission_group=PermissionGroup.ADMIN,
    )
    session.add(user)
    await session.commit()

    return Token(access_token=create_access_token(user.username))
