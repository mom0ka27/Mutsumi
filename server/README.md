# Mutsumi Server

## 运行要求

- Python 版本由 `.python-version` 指定。
- 本机部署需要安装 [uv](https://docs.astral.sh/uv/)。
- Docker 部署需要 Docker Engine 与 Docker Compose 插件。
- 首次部署前请复制并编辑 `config.yaml`，其中包含服务密钥、数据库地址和可选的 qBittorrent 凭据。

## 配置

从示例文件创建运行配置：

```bash
cp config.yaml.example config.yaml
chmod 600 config.yaml
```

- `auth.secret_key`：必须替换为随机且仅服务端持有的密钥；变更后现有登录令牌会失效。
- `database_url`：SQLAlchemy 异步连接 URL。默认 SQLite 路径为 `sqlite+aiosqlite:///./data/mutsumi.db`；使用 PostgreSQL 或 MySQL 时，需要额外安装对应异步驱动并确保数据库服务已创建。
- `storage.data_path`：服务端用于统计动画文件存储情况的路径。
- `qbittorrent.download_path`：传给 qBittorrent 的下载保存路径，可与 `storage.data_path` 不同。
- `server.ssl`：生产环境建议启用 TLS，并将证书、私钥设置为仅部署账户可读。
- `updates.repository`：允许服务端检查和下载更新的 GitHub 仓库，格式必须为 `owner/repo`。

## Docker 部署

1. 完成上方配置，若 qBittorrent 在宿主机运行，macOS 和 Windows 可将 `qbittorrent.url` 设为 `http://host.docker.internal:1234`。

2. 构建并在后台启动：

   ```bash
   docker compose up -d --build
   ```

3. 查看运行状态：

   ```bash
   docker compose ps
   docker compose logs -f server
   ```

服务默认监听 `http://localhost:12091`，健康检查地址为 `http://localhost:12091/api/v1/health`。

`compose.yaml` 会将整个 `server/` 目录挂载到 `/app`，让更新器替换的源文件直接持久化到宿主机。默认 SQLite 数据库、下载数据与日志分别保存在 `./data`、`./data` 和 `./logs`。请限制服务端目录的宿主机访问权限，不要向不可信用户开放 Docker Socket 或此目录的写权限。

## 本机部署

在 `server/` 目录执行：

```bash
./start.sh
```

启动脚本会根据 `uv.lock` 同步生产依赖并运行服务。请不要直接使用 `python run.py` 作为生产守护命令，否则更新器无法通过退出码自动重新拉起新版本。

## 服务端更新

仅管理员可在客户端的“服务端更新”页面检查并确认更新。更新器可查询正式 Release、Pre-release 或 `main` 分支；当前仅允许安装带 SHA-256 校验文件的 Release 和 Pre-release，分支仅用于查看最新提交。

每个可安装 Release 必须包含以下资产：

```text
mutsumi-server-{tag}.zip
mutsumi-server-{tag}.zip.sha256
```

工作流会打包 `server/` 下的发布文件并排除 `.DS_Store`。更新器会安全解压 ZIP，拒绝越界路径，并仅原子替换以下内容：`app/`、`run.py`、`pyproject.toml`、`uv.lock`、`.python-version`。`config.yaml`、`data/`、`logs/`、证书、`compose.yaml`、`Dockerfile` 和 `start.sh` 不会被自动覆盖。

`.sha256` 只能检测下载损坏或意外篡改，不能证明发布者身份；它与 ZIP 资产来自同一个 Release。仅应将 `updates.repository` 配置为受信任且已启用多因素认证、最小权限和受保护发布流程的仓库。若需要抵御仓库发布权限被盗用，应使用独立的发布签名与固定公钥验证机制。

更新校验与替换成功后，服务会以专用退出码结束；`start.sh` 会重新同步依赖并拉起 Python 进程。Docker 通过源码挂载保留更新结果，本机部署同样必须通过 `./start.sh` 运行。更新中断或替换失败时，更新器会尝试恢复已替换的文件；请始终保留 `data/` 与 `config.yaml` 的独立备份。
