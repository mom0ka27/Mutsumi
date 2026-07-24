import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse
from sqlalchemy import text

from app.api.router import api_router
from app.core.constants import API_VERSION, SERVER_VERSION
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
async def qbittorrent_error_handler(request: Request, exc: QBittorrentError):
    logger.warning(
        "qBittorrent business error: %s %s code=%s msg=%s",
        request.method,
        request.url.path,
        exc.code,
        exc.msg,
    )
    return JSONResponse(status_code=200, content={"code": exc.code, "msg": exc.msg})


@app.exception_handler(HTTPException)
async def http_exception_handler(request: Request, exc: HTTPException):
    logger.warning(
        "HTTP error: %s %s status=%s detail=%s",
        request.method,
        request.url.path,
        exc.status_code,
        exc.detail,
    )
    return JSONResponse(status_code=exc.status_code, content={"detail": exc.detail})


@app.exception_handler(Exception)
async def unhandled_exception_handler(request: Request, exc: Exception):
    logger.exception("Unhandled error: %s %s", request.method, request.url.path)
    return JSONResponse(status_code=500, content={"detail": "Internal server error"})


@app.get("/")
async def root():
    return {
        "message": "Mutsumi Server is running",
        "api_version": API_VERSION,
        "server_version": SERVER_VERSION,
    }


@app.get(f"/api/{API_VERSION}/health")
async def health():
    async with engine.connect() as conn:
        await conn.execute(text("SELECT 1"))
    return {
        "status": "ok",
        "api_version": API_VERSION,
        "server_version": SERVER_VERSION,
    }
