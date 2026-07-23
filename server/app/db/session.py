from sqlalchemy import event
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine
from sqlalchemy.orm import DeclarativeBase

from app.core.config import config

DATABASE_URL = config["database_url"]

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


async def init_db():
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
