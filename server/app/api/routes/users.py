from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.auth import (
    get_current_user,
    get_current_user_optional,
    get_password_hash,
    get_session,
    require_admin,
    verify_password,
)
from app.models import PermissionGroup, User
from app.schemas import PasswordChange, UserCreate, UserRead, UserUpdate

router = APIRouter(prefix="/users", tags=["users"])


def ensure_admin(current_user: User | None):
    if current_user is None or current_user.permission_group != PermissionGroup.ADMIN:
        raise HTTPException(status_code=403, detail="Admin permission required")


@router.get("/permission-groups", response_model=list[PermissionGroup])
async def list_permission_groups():
    return list(PermissionGroup)


@router.get("/me", response_model=UserRead)
async def get_me(current_user: User = Depends(get_current_user_optional)):
    if current_user is None:
        raise HTTPException(status_code=401, detail="Not authenticated")
    return current_user


@router.patch("/me/password", status_code=status.HTTP_204_NO_CONTENT)
async def change_password(
    payload: PasswordChange,
    session: AsyncSession = Depends(get_session),
    current_user: User = Depends(get_current_user),
):
    if not payload.new_password:
        raise HTTPException(status_code=422, detail="New password cannot be empty")
    if not await verify_password(payload.current_password, current_user.password_hash):
        raise HTTPException(status_code=400, detail="Current password is incorrect")

    current_user.password_hash = await get_password_hash(payload.new_password)
    current_user.token_version += 1
    await session.commit()


@router.get("", response_model=list[UserRead], dependencies=[Depends(require_admin)])
async def list_users(
    session: AsyncSession = Depends(get_session),
    skip: int = Query(default=0, ge=0),
    limit: int = Query(default=100, ge=1, le=1000),
):
    result = await session.scalars(
        select(User).order_by(User.id).offset(skip).limit(limit)
    )
    return list(result)


@router.post("", response_model=UserRead, status_code=status.HTTP_201_CREATED)
async def create_user(
    payload: UserCreate,
    session: AsyncSession = Depends(get_session),
    current_user: User | None = Depends(get_current_user_optional),
):
    total_users = await session.scalar(select(func.count()).select_from(User))
    if total_users != 0:
        ensure_admin(current_user)

    exists = await session.scalar(select(User).where(User.username == payload.username))
    if exists:
        raise HTTPException(status_code=409, detail="Username already exists")

    user = User(
        username=payload.username,
        password_hash=await get_password_hash(payload.password),
        permission_group=payload.permission_group,
    )
    session.add(user)
    await session.commit()
    await session.refresh(user)
    return user


@router.get("/{user_id}", response_model=UserRead, dependencies=[Depends(require_admin)])
async def get_user(user_id: int, session: AsyncSession = Depends(get_session)):
    user = await session.get(User, user_id)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    return user


@router.patch("/{user_id}", response_model=UserRead, dependencies=[Depends(require_admin)])
async def update_user(
    user_id: int,
    payload: UserUpdate,
    session: AsyncSession = Depends(get_session),
):
    user = await session.get(User, user_id)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    if payload.username is not None:
        exists = await session.scalar(
            select(User).where(User.username == payload.username, User.id != user_id)
        )
        if exists:
            raise HTTPException(status_code=409, detail="Username already exists")
        user.username = payload.username

    if payload.password is not None:
        user.password_hash = await get_password_hash(payload.password)

    if payload.permission_group is not None:
        user.permission_group = payload.permission_group

    await session.commit()
    await session.refresh(user)
    return user


@router.delete("/{user_id}", status_code=status.HTTP_204_NO_CONTENT, dependencies=[Depends(require_admin)])
async def delete_user(user_id: int, session: AsyncSession = Depends(get_session)):
    user = await session.get(User, user_id)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    await session.delete(user)
    await session.commit()
