import logging
from pathlib import Path

from alembic import command
from alembic.config import Config
from sqlalchemy import event, inspect
from sqlalchemy.engine import Connection
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine
from sqlalchemy.orm import DeclarativeBase

from app.core.config import config

logger = logging.getLogger(__name__)

DATABASE_URL = config["database_url"]

ALEMBIC_INI_PATH = Path(__file__).resolve().parent.parent.parent / "alembic.ini"
INITIAL_REVISION = "0001_initial"

engine_kwargs = {}
if DATABASE_URL.startswith("sqlite+aiosqlite://"):
    engine_kwargs["connect_args"] = {"timeout": 10}

engine = create_async_engine(DATABASE_URL, **engine_kwargs)

if DATABASE_URL.startswith("sqlite+aiosqlite://"):

    @event.listens_for(engine.sync_engine, "connect")
    def configure_sqlite_connection(dbapi_connection, connection_record):
        cursor = dbapi_connection.cursor()
        try:
            cursor.execute("PRAGMA journal_mode=WAL")
            cursor.execute("PRAGMA busy_timeout=10000")
        finally:
            cursor.close()


AsyncSessionLocal = async_sessionmaker(engine, expire_on_commit=False)


class Base(DeclarativeBase):
    pass


def alembic_config() -> Config:
    return Config(str(ALEMBIC_INI_PATH))


def _upgrade_to_head(connection: Connection) -> None:
    alembic_cfg = alembic_config()
    alembic_cfg.attributes["connection"] = connection

    tables = set(inspect(connection).get_table_names())
    if "alembic_version" not in tables and "users" in tables:
        # Database predates Alembic: it was created by metadata.create_all and
        # already matches the initial revision, so record that before upgrading.
        logger.info("Stamping pre-Alembic database at %s", INITIAL_REVISION)
        command.stamp(alembic_cfg, INITIAL_REVISION)

    command.upgrade(alembic_cfg, "head")


async def init_db():
    # Importing the models registers them on Base.metadata, which Alembic's
    # autogenerate compares against.
    import app.models  # noqa: F401

    async with engine.begin() as conn:
        await conn.run_sync(_upgrade_to_head)
