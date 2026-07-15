import asyncio
import hashlib
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
from app.schemas.update import UpdateChannel

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
    checksum_url: str | None


class ServerUpdateService:
    _repository_pattern = re.compile(r"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$")
    _update_lock = asyncio.Lock()

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
            candidate = await self.get_candidate(channel)
            if candidate.checksum_url is None:
                raise RuntimeError("当前更新通道不支持 SHA-256 校验")
            archive = await self._download(candidate.download_url)
            try:
                checksum = await self._download_text(candidate.checksum_url)
                self._verify_checksum(archive, checksum)
                await asyncio.to_thread(self._replace_files, archive)
            finally:
                archive.unlink(missing_ok=True)
            logger.warning("服务端更新完成，正在重启至 %s", candidate.version)
        os._exit(75)

    async def _release_candidate(
        self,
        client: httpx.AsyncClient,
        repository: str,
        channel: UpdateChannel,
    ) -> UpdateCandidate:
        if channel == UpdateChannel.RELEASE:
            response = await client.get(f"https://api.github.com/repos/{repository}/releases/latest")
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
            checksum_url=f"{asset.get('browser_download_url')}.sha256",
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
            checksum_url=None,
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

    async def _download_text(self, url: str) -> str:
        async with httpx.AsyncClient(timeout=httpx.Timeout(15.0), follow_redirects=True) as client:
            response = await client.get(url)
            response.raise_for_status()
            return response.text

    def _replace_files(self, archive: Path) -> None:
        root = Path(__file__).resolve().parents[2]
        with tempfile.TemporaryDirectory(dir=root.parent) as temp_dir:
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

    def _verify_checksum(self, archive: Path, checksum_text: str) -> None:
        expected = checksum_text.strip().split()[0].lower()
        if not re.fullmatch(r"[a-f0-9]{64}", expected):
            raise RuntimeError("更新包 SHA-256 校验文件无效")
        actual = hashlib.sha256(archive.read_bytes()).hexdigest()
        if actual != expected:
            raise RuntimeError("更新包 SHA-256 校验失败")

    def _repository(self) -> str:
        repository = str(config["updates"]["repository"]).strip()
        if not self._repository_pattern.fullmatch(repository):
            raise RuntimeError("更新仓库配置无效")
        return repository

    def _asset_name(self, tag: str) -> str:
        template = str(config["updates"]["asset_template"])
        return template.replace("{tag}", tag)


server_update_service = ServerUpdateService()
