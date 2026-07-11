import logging
from logging.handlers import TimedRotatingFileHandler
from pathlib import Path

from app.core.config import config

LOG_FORMAT = "%(asctime)s | %(levelname)-8s | %(name)s | %(message)s"
DATE_FORMAT = "%Y-%m-%d %H:%M:%S"

LEVEL_COLORS = {
    logging.DEBUG: "\033[36m",
    logging.INFO: "\033[0m",
    logging.WARNING: "\033[33m",
    logging.ERROR: "\033[31m",
    logging.CRITICAL: "\033[35m",
}
RESET_COLOR = "\033[0m"


class ColorFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        color = LEVEL_COLORS.get(record.levelno)
        if not color:
            return super().format(record)

        record.msg = f"{color}{record.getMessage()}{RESET_COLOR}"
        record.name = f"\033[36m{record.name}{RESET_COLOR}"
        record.levelname = f"{color}{record.levelname}{RESET_COLOR}"
        record.args = ()
        return super().format(record)

def setup_logging() -> None:
    logging_config = config["logging"]
    log_level = getattr(logging, logging_config["level"].upper(), logging.INFO)
    log_dir = Path(logging_config["directory"])
    retention_days = int(logging_config["retention_days"])

    log_dir.mkdir(parents=True, exist_ok=True)

    root_logger = logging.getLogger()
    root_logger.setLevel(log_level)
    root_logger.handlers.clear()

    console_handler = logging.StreamHandler()
    console_handler.setLevel(log_level)
    console_handler.setFormatter(ColorFormatter(LOG_FORMAT, datefmt=DATE_FORMAT))

    file_handler = TimedRotatingFileHandler(
        filename=log_dir / "server.log",
        when="midnight",
        interval=1,
        backupCount=retention_days,
        encoding="utf-8",
    )
    file_handler.suffix = "%Y-%m-%d"
    file_handler.setLevel(log_level)
    file_handler.setFormatter(logging.Formatter(LOG_FORMAT, datefmt=DATE_FORMAT))

    root_logger.addHandler(console_handler)
    root_logger.addHandler(file_handler)

    for logger_name in ("uvicorn", "uvicorn.error", "uvicorn.access"):
        logger = logging.getLogger(logger_name)
        logger.handlers.clear()
        logger.propagate = True
        logger.setLevel(log_level)
