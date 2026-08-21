import asyncio
import os
import stat
from pathlib import Path
from secrets import token_urlsafe
from typing import Any

import yaml

DEFAULT_CONFIG_PATH = Path(__file__).resolve().parent.parent.parent / "config.yaml"

# Overridable so tests (and alternative deployments) can point at their own
# file instead of writing to the checkout.
CONFIG_PATH = Path(os.environ.get("MUTSUMI_CONFIG_PATH") or DEFAULT_CONFIG_PATH)

DEFAULT_CONFIG: dict[str, Any] = {
    "server": {
        "name": "Mutsumi Server",
        "host": "0.0.0.0",
        "port": 12091,
        "reload": False,
        "ssl": {
            "enabled": False,
            "certfile": None,
            "keyfile": None,
        },
    },
    "logging": {
        "level": "INFO",
        "directory": "logs",
        "retention_days": 7,
    },
    "storage": {
        "data_path": "./data",
        "status_cache_seconds": 60,
    },
    "database_url": "sqlite+aiosqlite:///./data/mutsumi.db",
    "updates": {
        "repository": "mom0ka27/Mutsumi",
        "asset_template": "mutsumi-server-{tag}.zip",
        "default_branch": "main",
        "channel": "release",
    },
    "auth": {
        "secret_key": None,
        "algorithm": "HS256",
        "access_token_expire_minutes": 60 * 24,
    },
    "qbittorrent": {
        "url": "",
        "username": "",
        "password": "",
        "download_path": "",
        "share_ratio_limit": 3.0,
    },
    "subscription": {
        "enabled": True,
        "interval_minutes": 15,
        "cold_start_days": 7,
        # Resources per feed page. 100 is the feed's own default, and asking for
        # more than it will honour gets silently answered with a 100-item page.
        "page_size": 100,
        # A runaway guard on the page walk, not a window: a check pages until the
        # feed says there is no more, or until it has a release for every aired
        # episode it is missing. Stopping here means results were truncated.
        "max_pages": 200,
        # How many of a show's names (中文名, 原名, 别名…) get their own feed
        # query. Each one costs a request, so the cap keeps a subject with a
        # dozen 别名 from turning one check into dozens.
        "max_name_variants": 4,
        "auto_import": True,
    },
}


def load_config() -> dict[str, Any]:
    if CONFIG_PATH.exists():
        with CONFIG_PATH.open("r", encoding="utf-8") as file:
            config = yaml.safe_load(file) or {}
    else:
        config = {}

    config = merge_config(DEFAULT_CONFIG, config)

    if not config["auth"].get("secret_key"):
        config["auth"]["secret_key"] = token_urlsafe(48)
        _save_config_sync(config)
    else:
        _ensure_permissions()

    return config


async def save_config(config: dict[str, Any]) -> None:
    await asyncio.to_thread(_save_config_sync, config)


def _save_config_sync(config: dict[str, Any]) -> None:
    with CONFIG_PATH.open("w", encoding="utf-8") as file:
        yaml.safe_dump(config, file, sort_keys=False)
    _ensure_permissions()


def _ensure_permissions() -> None:
    try:
        current = os.stat(CONFIG_PATH).st_mode
        if current & stat.S_IRWXG or current & stat.S_IRWXO:
            os.chmod(CONFIG_PATH, stat.S_IRUSR | stat.S_IWUSR)
    except OSError:
        pass


def merge_config(default: dict[str, Any], current: dict[str, Any]) -> dict[str, Any]:
    merged = default.copy()
    for key, value in current.items():
        if isinstance(value, dict) and isinstance(merged.get(key), dict):
            merged[key] = merge_config(merged[key], value)
        else:
            merged[key] = value
    return merged


config = load_config()
