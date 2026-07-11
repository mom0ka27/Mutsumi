import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.responses import JSONResponse
from sqlalchemy import text

from app.api.router import api_router
from app.core.constants import API_VERSION
from app.core.qbittorrent_error import QBittorrentError
from app.db.session import engine, init_db
from app.models import User

logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    await init_db()
    logger.info("Database initialized")
    yield


app = FastAPI(title="Mutsumi Server", lifespan=lifespan)
app.include_router(api_router)


@app.exception_handler(QBittorrentError)
async def qbittorrent_error_handler(_, exc: QBittorrentError):
    return JSONResponse(status_code=200, content={"code": exc.code, "msg": exc.msg})


@app.get("/")
async def root():
    return {"message": "Mutsumi Server is running", "api_version": API_VERSION}


@app.get(f"/api/{API_VERSION}/health")
async def health():
    async with engine.connect() as conn:
        await conn.execute(text("SELECT 1"))
    return {"status": "ok", "api_version": API_VERSION}
