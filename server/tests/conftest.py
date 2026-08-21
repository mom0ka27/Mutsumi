"""Test bootstrap.

`app.core.config` and `app.db.session` read their settings at import time, so
the config file has to exist and be pointed at before anything under `app.` is
imported. pytest loads conftest first, which makes this module the right place.
"""

import os
import tempfile
from pathlib import Path

import pytest
import yaml

_TMP_ROOT = Path(tempfile.mkdtemp(prefix="mutsumi-tests-"))
_DATA_PATH = _TMP_ROOT / "data"
_DATA_PATH.mkdir(parents=True, exist_ok=True)

_CONFIG_PATH = _TMP_ROOT / "config.yaml"
_CONFIG_PATH.write_text(
    yaml.safe_dump(
        {
            "server": {"name": "Test Server"},
            "logging": {"level": "WARNING", "directory": str(_TMP_ROOT / "logs")},
            "storage": {
                "data_path": str(_DATA_PATH),
                # Disable the TTL cache so storage tests see live sizes.
                "status_cache_seconds": 0,
            },
            "database_url": f"sqlite+aiosqlite:///{_TMP_ROOT / 'test.db'}",
            "auth": {"secret_key": "test-secret-key", "algorithm": "HS256"},
            "qbittorrent": {"url": "", "username": "", "password": ""},
        }
    ),
    encoding="utf-8",
)
os.environ["MUTSUMI_CONFIG_PATH"] = str(_CONFIG_PATH)

from fastapi.testclient import TestClient  # noqa: E402

from app.core.auth import get_password_hash  # noqa: E402
from app.db.session import AsyncSessionLocal  # noqa: E402
from app.main import app  # noqa: E402
from app.models import (  # noqa: E402
    Anime,
    Episode,
    PermissionGroup,
    PreferenceProfile,
    Subscription,
    SubscriptionEpisode,
    User,
    WatchProgress,
)

ADMIN_PASSWORD = "admin-password"


@pytest.fixture(scope="session")
def data_path() -> Path:
    # resolve() so comparisons match the service, which resolves its paths
    # (/var is a symlink to /private/var on macOS).
    return _DATA_PATH.resolve()


@pytest.fixture(scope="session")
def client():
    # Entering the context runs the lifespan, which applies the migrations.
    with TestClient(app) as test_client:
        yield test_client


@pytest.fixture(autouse=True)
async def clean_database(client):
    """Depends on `client` so the schema exists before the truncation runs."""
    yield
    async with AsyncSessionLocal() as session:
        for model in (
            SubscriptionEpisode,
            Subscription,
            WatchProgress,
            Episode,
            Anime,
            PreferenceProfile,
            User,
        ):
            await session.execute(model.__table__.delete())
        await session.commit()


async def create_user(username: str, group: PermissionGroup) -> None:
    async with AsyncSessionLocal() as session:
        session.add(
            User(
                username=username,
                password_hash=await get_password_hash(ADMIN_PASSWORD),
                permission_group=group,
            )
        )
        await session.commit()


@pytest.fixture
async def token_for(client):
    """Returns a callable that creates a user in `group` and logs them in."""

    async def _token_for(group: PermissionGroup) -> str:
        username = f"{group.value.lower()}-user"
        await create_user(username, group)
        response = client.post(
            "/api/v1/auth/login",
            data={"username": username, "password": ADMIN_PASSWORD},
        )
        assert response.status_code == 200, response.text
        return response.json()["access_token"]

    return _token_for


@pytest.fixture
async def auth_headers(token_for):
    async def _headers(group: PermissionGroup) -> dict[str, str]:
        return {"Authorization": f"Bearer {await token_for(group)}"}

    return _headers
