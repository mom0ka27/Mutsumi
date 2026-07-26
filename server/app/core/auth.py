import asyncio
from datetime import UTC, datetime, timedelta

import bcrypt
from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from jose import JWTError, jwt
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import config
from app.db.session import AsyncSessionLocal
from app.models import PermissionGroup, User

auth_config = config["auth"]
SECRET_KEY = auth_config["secret_key"]
ALGORITHM = auth_config["algorithm"]
ACCESS_TOKEN_EXPIRE_MINUTES = auth_config["access_token_expire_minutes"]

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/api/v1/auth/login")
optional_oauth2_scheme = OAuth2PasswordBearer(
    tokenUrl="/api/v1/auth/login",
    auto_error=False,
)

# bcrypt only hashes the first 72 bytes and newer releases raise instead of
# truncating, so truncate here to stay compatible with hashes written earlier.
BCRYPT_MAX_PASSWORD_BYTES = 72


async def get_session():
    async with AsyncSessionLocal() as session:
        yield session


def _encode_password(password: str) -> bytes:
    return password.encode("utf-8")[:BCRYPT_MAX_PASSWORD_BYTES]


def _verify_password_sync(plain_password: str, password_hash: str) -> bool:
    try:
        return bcrypt.checkpw(
            _encode_password(plain_password),
            password_hash.encode("utf-8"),
        )
    except ValueError:
        # Malformed or unsupported hash in the database.
        return False


def _hash_password_sync(password: str) -> str:
    return bcrypt.hashpw(_encode_password(password), bcrypt.gensalt()).decode("utf-8")


async def verify_password(plain_password: str, password_hash: str) -> bool:
    return await asyncio.to_thread(_verify_password_sync, plain_password, password_hash)


async def get_password_hash(password: str) -> str:
    return await asyncio.to_thread(_hash_password_sync, password)


def create_access_token(subject: str, token_version: int = 0) -> str:
    expire = datetime.now(UTC) + timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    payload = {"sub": subject, "exp": expire, "ver": token_version}
    return jwt.encode(payload, SECRET_KEY, algorithm=ALGORITHM)


async def authenticate_user(
    username: str,
    password: str,
    session: AsyncSession,
) -> User | None:
    user = await session.scalar(select(User).where(User.username == username))
    if not user or not await verify_password(password, user.password_hash):
        return None
    return user


async def get_current_user(
    token: str = Depends(oauth2_scheme),
    session: AsyncSession = Depends(get_session),
) -> User:
    return await get_user_from_token(token, session)


async def get_current_user_optional(
    token: str | None = Depends(optional_oauth2_scheme),
    session: AsyncSession = Depends(get_session),
) -> User | None:
    if token is None:
        return None
    return await get_user_from_token(token, session)


async def get_user_from_token(token: str, session: AsyncSession) -> User:
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Invalid authentication credentials",
        headers={"WWW-Authenticate": "Bearer"},
    )
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        username = payload.get("sub")
        if username is None:
            raise credentials_exception
        token_version = payload.get("ver", 0)
    except JWTError as exc:
        raise credentials_exception from exc

    user = await session.scalar(select(User).where(User.username == username))
    if user is None or user.token_version != token_version:
        raise credentials_exception
    return user


def require_admin(current_user: User = Depends(get_current_user)) -> User:
    if current_user.permission_group != PermissionGroup.ADMIN:
        raise HTTPException(status_code=403, detail="Admin permission required")
    return current_user


def require_download_permission(
    current_user: User = Depends(get_current_user),
) -> User:
    if current_user.permission_group == PermissionGroup.GUEST:
        raise HTTPException(status_code=403, detail="Download permission required")
    return current_user
