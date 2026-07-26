"""Schema changes ship as Alembic revisions, and databases created before
Alembic existed have to be adopted rather than re-created."""

import sqlite3

from sqlalchemy.ext.asyncio import create_async_engine

from app.db import session as session_module
from app.db.session import INITIAL_REVISION, Base, _upgrade_to_head


async def _run_migrations(db_path) -> None:
    engine = create_async_engine(f"sqlite+aiosqlite:///{db_path}")
    try:
        async with engine.begin() as conn:
            await conn.run_sync(_upgrade_to_head)
    finally:
        await engine.dispose()


def _tables(db_path) -> set[str]:
    connection = sqlite3.connect(db_path)
    try:
        return {
            row[0]
            for row in connection.execute(
                "select name from sqlite_master where type='table'"
            )
        }
    finally:
        connection.close()


def _version(db_path) -> str:
    connection = sqlite3.connect(db_path)
    try:
        return connection.execute("select version_num from alembic_version").fetchone()[0]
    finally:
        connection.close()


async def test_fresh_database_gets_the_full_schema(tmp_path):
    db_path = tmp_path / "fresh.db"
    await _run_migrations(db_path)

    assert {"anime", "episodes", "users", "watch_progress"} <= _tables(db_path)
    assert _version(db_path)


async def test_pre_alembic_database_is_stamped_and_keeps_its_rows(tmp_path):
    db_path = tmp_path / "legacy.db"

    # Build the database the way the old init_db did.
    engine = create_async_engine(f"sqlite+aiosqlite:///{db_path}")
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    await engine.dispose()

    connection = sqlite3.connect(db_path)
    connection.execute(
        "insert into users (username, password_hash, permission_group, token_version)"
        " values ('legacy-admin', 'hash', 'ADMIN', 0)"
    )
    connection.commit()
    connection.close()

    assert "alembic_version" not in _tables(db_path)

    await _run_migrations(db_path)

    assert _version(db_path) == INITIAL_REVISION
    connection = sqlite3.connect(db_path)
    try:
        assert connection.execute("select username from users").fetchall() == [
            ("legacy-admin",)
        ]
    finally:
        connection.close()


async def test_migrating_twice_is_a_no_op(tmp_path):
    db_path = tmp_path / "twice.db"
    await _run_migrations(db_path)
    first = _version(db_path)
    await _run_migrations(db_path)
    assert _version(db_path) == first


def test_alembic_config_points_at_the_migrations_directory():
    config = session_module.alembic_config()
    script_location = config.get_main_option("script_location")
    assert script_location and script_location.endswith("migrations")
