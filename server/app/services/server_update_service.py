import asyncio
import logging
import os
import re
import shutil
import tempfile
import zipfile
from dataclasses import dataclass
from pathlib import Path

import httpx

from app.core.config import config
from app.core.constants import SERVER_VERSION
from app.schemas.update import UpdateChannel
from app.schemas.update import UpdateStatus

logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class UpdateCandidate:
    channel: UpdateChannel
    version: str
    name: str
    notes: str
    published_at: str | None
    release_url: str
    download_url: str


class ServerUpdateService:
    _repository_pattern = re.compile(r"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$")
    _update_lock = asyncio.Lock()
    _build_info_path = Path(__file__).resolve().parents[2] / ".build-info"
    _status = UpdateStatus.RUNNING
    _channel: UpdateChannel | None = None
    _target_version = ""
    _message = "服务端正在运行"

    async def get_candidate(self, channel: UpdateChannel) -> UpdateCandidate:
        repository = self._repository()
        timeout = httpx.Timeout(15.0)
        headers = {"Accept": "application/vnd.github+json", "User-Agent": "Mutsumi-Server"}
        async with httpx.AsyncClient(timeout=timeout, headers=headers) as client:
            if channel == UpdateChannel.BRANCH:
                return await self._branch_candidate(client, repository)
            return await self._release_candidate(client, repository, channel)

    async def apply_update(self, channel: UpdateChannel) -> None:
        async with self._update_lock:
            try:
                candidate = await self.get_candidate(channel)
                self._set_status(
                    UpdateStatus.DOWNLOADING,
                    channel=channel,
                    target_version=candidate.version,
                    message="正在下载更新包",
                )
                archive = await self._download(candidate.download_url)
                try:
                    self._set_status(
                        UpdateStatus.INSTALLING,
                        message="正在替换服务端文件",
                    )
                    await asyncio.to_thread(self._replace_files, archive)
                    if channel == UpdateChannel.BRANCH:
                        await asyncio.to_thread(self._write_build_commit, candidate.version)
                finally:
                    archive.unlink(missing_ok=True)
            except Exception as exc:
                self._set_status(UpdateStatus.FAILED, message=str(exc))
                logger.exception("服务端更新失败")
                return
            logger.warning("服务端更新完成，正在重启至 %s", candidate.version)
        os._exit(75)

    def begin_update(self, channel: UpdateChannel) -> dict[str, object] | None:
        if self._status in {UpdateStatus.DOWNLOADING, UpdateStatus.INSTALLING}:
            return None
        self._set_status(
            UpdateStatus.DOWNLOADING,
            channel=channel,
            target_version="",
            message="正在获取更新信息",
        )
        return self.update_status()

    def update_status(self) -> dict[str, object]:
        return {
            "status": self._status,
            "channel": self._channel,
            "target_version": self._target_version,
            "message": self._message,
        }

    def _set_status(
        self,
        status: UpdateStatus,
        *,
        channel: UpdateChannel | None = None,
        target_version: str | None = None,
        message: str,
    ) -> None:
        self._status = status
        if channel is not None:
            self._channel = channel
        if target_version is not None:
            self._target_version = target_version
        self._message = message

    async def _release_candidate(
        self,
        client: httpx.AsyncClient,
        repository: str,
        channel: UpdateChannel,
    ) -> UpdateCandidate:
        if channel == UpdateChannel.RELEASE:
            response = await client.get(f"https://api.github.com/repos/{repository}/releases/latest")
            if response.status_code == 404:
                return UpdateCandidate(
                    channel=channel,
                    version=SERVER_VERSION,
                    name="暂无正式发布版本",
                    notes="GitHub 仓库尚未创建正式 Release。",
                    published_at=None,
                    release_url=f"https://github.com/{repository}/releases",
                    download_url="",
                )
            response.raise_for_status()
            release = response.json()
        else:
            response = await client.get(f"https://api.github.com/repos/{repository}/releases")
            response.raise_for_status()
            release = next((item for item in response.json() if item.get("prerelease")), None)
            if release is None:
                raise RuntimeError("未找到预发布版本")
        tag = release.get("tag_name")
        if not isinstance(tag, str) or not tag:
            raise RuntimeError("GitHub Release 缺少标签")
        asset_name = self._asset_name(tag)
        asset = next(
            (item for item in release.get("assets", []) if item.get("name") == asset_name),
            None,
        )
        if asset is None:
            raise RuntimeError(f"Release 缺少更新包 {asset_name}")
        return UpdateCandidate(
            channel=channel,
            version=tag,
            name=str(release.get("name") or tag),
            notes=str(release.get("body") or ""),
            published_at=release.get("published_at"),
            release_url=str(release.get("html_url") or ""),
            download_url=str(asset.get("browser_download_url") or ""),
        )

    async def _branch_candidate(
        self, client: httpx.AsyncClient, repository: str
    ) -> UpdateCandidate:
        branch = str(config["updates"]["default_branch"])
        response = await client.get(
            f"https://api.github.com/repos/{repository}/commits/{branch}"
        )
        response.raise_for_status()
        commit = response.json()
        sha = str(commit.get("sha") or "")
        if not sha:
            raise RuntimeError("GitHub 分支缺少提交信息")
        commit_info = commit.get("commit") if isinstance(commit.get("commit"), dict) else {}
        return UpdateCandidate(
            channel=UpdateChannel.BRANCH,
            version=sha[:12],
            name=f"{branch}@{sha[:12]}",
            notes=str(commit_info.get("message") or ""),
            published_at=commit_info.get("author", {}).get("date"),
            release_url=str(commit.get("html_url") or ""),
            download_url=f"https://github.com/{repository}/archive/{sha}.zip",
        )

    async def _download(self, url: str) -> Path:
        if not url.startswith("https://"):
            raise RuntimeError("更新包下载地址不安全")
        async with httpx.AsyncClient(timeout=httpx.Timeout(60.0), follow_redirects=True) as client:
            response = await client.get(url)
            response.raise_for_status()
        with tempfile.NamedTemporaryFile(suffix=".zip", delete=False) as file:
            file.write(response.content)
            return Path(file.name)

    def _replace_files(self, archive: Path) -> None:
        root = Path(__file__).resolve().parents[2]
        with tempfile.TemporaryDirectory(dir=root) as temp_dir:
            extracted = Path(temp_dir) / "extracted"
            extracted.mkdir()
            with zipfile.ZipFile(archive) as zip_file:
                self._extract_safely(zip_file, extracted)
            source = self._source_root(extracted)
            required = ("app", "run.py", "pyproject.toml", "uv.lock", ".python-version")
            if any(not (source / name).exists() for name in required):
                raise RuntimeError("更新包缺少必要服务端文件")
            backup = Path(temp_dir) / "backup"
            backup.mkdir()
            replaced: list[str] = []
            try:
                for name in required:
                    target = root / name
                    if target.exists():
                        os.replace(target, backup / name)
                    os.replace(source / name, target)
                    replaced.append(name)
            except Exception:
                for name in reversed(replaced):
                    target = root / name
                    if target.exists():
                        if target.is_dir():
                            shutil.rmtree(target)
                        else:
                            target.unlink()
                    previous = backup / name
                    if previous.exists():
                        os.replace(previous, target)
                raise

    def current_build_commit(self) -> str | None:
        try:
            value = self._build_info_path.read_text(encoding="utf-8").strip()
        except OSError:
            return None
        return value if re.fullmatch(r"[a-f0-9]{7,40}", value) else None

    def _write_build_commit(self, commit: str) -> None:
        if not re.fullmatch(r"[a-f0-9]{7,40}", commit):
            raise RuntimeError("GitHub 分支提交哈希无效")
        temporary_path = self._build_info_path.with_suffix(".tmp")
        temporary_path.write_text(f"{commit}\n", encoding="utf-8")
        os.replace(temporary_path, self._build_info_path)

    def _extract_safely(self, zip_file: zipfile.ZipFile, target: Path) -> None:
        target_resolved = target.resolve()
        for info in zip_file.infolist():
            destination = (target / info.filename).resolve()
            if not destination.is_relative_to(target_resolved):
                raise RuntimeError("更新包包含不安全路径")
        zip_file.extractall(target)

    def _source_root(self, extracted: Path) -> Path:
        children = list(extracted.iterdir())
        if len(children) == 1 and children[0].is_dir():
            source = children[0]
            if (source / "server").is_dir():
                return source / "server"
            return source
        return extracted

    def _repository(self) -> str:
        repository = str(config["updates"]["repository"]).strip()
        if not self._repository_pattern.fullmatch(repository):
            raise RuntimeError("更新仓库配置无效")
        return repository

    def _asset_name(self, tag: str) -> str:
        template = str(config["updates"]["asset_template"])
        return template.replace("{tag}", tag)


server_update_service = ServerUpdateService()
