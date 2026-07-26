import bcrypt
import pytest

from app.core.auth import (
    BCRYPT_MAX_PASSWORD_BYTES,
    create_access_token,
    get_password_hash,
    verify_password,
)
from app.models import PermissionGroup


async def test_hash_roundtrip():
    password_hash = await get_password_hash("hunter2")
    assert await verify_password("hunter2", password_hash)
    assert not await verify_password("hunter3", password_hash)


@pytest.mark.parametrize("ident", [b"2a", b"2b"])
async def test_verifies_hashes_written_by_passlib(ident):
    """passlib wrote $2a$/$2b$ bcrypt hashes; those must still authenticate."""
    legacy = bcrypt.hashpw(b"hunter2", bcrypt.gensalt(prefix=ident)).decode()
    assert await verify_password("hunter2", legacy)


async def test_password_longer_than_bcrypt_limit_is_accepted():
    # bcrypt only reads the first 72 bytes; newer releases raise instead of
    # truncating, so the truncation has to happen in our code.
    password = "a" * (BCRYPT_MAX_PASSWORD_BYTES + 40)
    password_hash = await get_password_hash(password)
    assert await verify_password(password, password_hash)


async def test_multibyte_password_is_not_rejected():
    password = "密码" * 40  # well over 72 bytes once encoded
    password_hash = await get_password_hash(password)
    assert await verify_password(password, password_hash)


async def test_malformed_hash_does_not_raise():
    assert not await verify_password("anything", "not-a-bcrypt-hash")


def test_login_rejects_wrong_password(client):
    assert (
        client.post(
            "/api/v1/auth/login",
            data={"username": "nobody", "password": "wrong"},
        ).status_code
        == 401
    )


async def test_token_version_bump_invalidates_old_token(client, token_for):
    from app.db.session import AsyncSessionLocal
    from sqlalchemy import select

    from app.models import User

    token = await token_for(PermissionGroup.ADMIN)
    headers = {"Authorization": f"Bearer {token}"}
    assert client.get("/api/v1/anime", headers=headers).status_code == 200

    async with AsyncSessionLocal() as session:
        user = await session.scalar(select(User).where(User.username == "admin-user"))
        user.token_version += 1
        await session.commit()

    assert client.get("/api/v1/anime", headers=headers).status_code == 401


def test_unauthenticated_request_is_rejected(client):
    assert client.get("/api/v1/anime").status_code == 401


def test_token_signed_with_other_key_is_rejected(client):
    from jose import jwt

    forged = jwt.encode({"sub": "admin-user", "ver": 0}, "other-key", algorithm="HS256")
    assert (
        client.get(
            "/api/v1/anime", headers={"Authorization": f"Bearer {forged}"}
        ).status_code
        == 401
    )


def test_create_access_token_is_decodable():
    from jose import jwt

    from app.core.auth import ALGORITHM, SECRET_KEY

    payload = jwt.decode(
        create_access_token("someone", 3), SECRET_KEY, algorithms=[ALGORITHM]
    )
    assert payload["sub"] == "someone"
    assert payload["ver"] == 3
