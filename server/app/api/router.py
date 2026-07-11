from fastapi import APIRouter

from app.api.routes import anime, auth, config, qbittorrent, setup, users
from app.core.constants import API_PREFIX

api_router = APIRouter(prefix=API_PREFIX)
api_router.include_router(setup.router)
api_router.include_router(auth.router)
api_router.include_router(users.router)
api_router.include_router(config.router)
api_router.include_router(anime.router)
api_router.include_router(qbittorrent.router)
