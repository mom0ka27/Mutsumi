import hashlib
import logging
import re
import ssl
from pathlib import Path
from typing import Any

import uvicorn

from app.core.config import config
from app.core.logging import setup_logging

server_config = config["server"]
logger = logging.getLogger(__name__)


def _resolve_path(value: str) -> Path:
    path = Path(value).expanduser()
    if path.is_absolute():
        return path
    return Path(__file__).resolve().parent / path


def _certificate_sha256_fingerprint(certfile: Path) -> str:
    content = certfile.read_text(encoding="utf-8")
    match = re.search(
        r"-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----",
        content,
        re.DOTALL,
    )
    if not match:
        raise RuntimeError(
            f"SSL certificate file does not contain a PEM certificate: {certfile}"
        )

    der_certificate = ssl.PEM_cert_to_DER_cert(match.group(0))
    digest = hashlib.sha256(der_certificate).hexdigest().upper()
    return ":".join(digest[index : index + 2] for index in range(0, len(digest), 2))


def _ssl_options() -> dict[str, Any]:
    ssl_config = server_config.get("ssl", {})
    if not ssl_config.get("enabled"):
        return {}

    certfile_value = ssl_config.get("certfile")
    keyfile_value = ssl_config.get("keyfile")
    if not certfile_value or not keyfile_value:
        raise RuntimeError(
            "SSL is enabled, but server.ssl.certfile or server.ssl.keyfile is not configured"
        )

    certfile = _resolve_path(str(certfile_value))
    keyfile = _resolve_path(str(keyfile_value))
    if not certfile.exists():
        raise RuntimeError(f"SSL certificate file does not exist: {certfile}")
    if not keyfile.exists():
        raise RuntimeError(f"SSL key file does not exist: {keyfile}")

    logger.info("SSL enabled")
    logger.info("SSL certificate: %s", certfile)
    logger.info("SSL SHA-256 fingerprint: %s", _certificate_sha256_fingerprint(certfile))

    return {
        "ssl_certfile": str(certfile),
        "ssl_keyfile": str(keyfile),
    }


if __name__ == "__main__":
    setup_logging()
    ssl_options = _ssl_options()
    protocol = "https" if ssl_options else "http"
    logger.info(
        "Starting Mutsumi Server on %s://%s:%s",
        protocol,
        server_config["host"],
        server_config["port"],
    )
    uvicorn.run(
        "app.main:app",
        host=server_config["host"],
        port=server_config["port"],
        reload=server_config.get("reload", False),
        # log_config=None,
        workers=1,
        **ssl_options,
    )
