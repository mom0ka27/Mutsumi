# Mutsumi Server

## Docker 部署

1. 在本目录创建运行配置：

   ```bash
   cp config.yaml.example config.yaml
   ```

2. 编辑 `config.yaml`，至少将 `auth.secret_key` 替换为安全的随机值；若 qBittorrent 在宿主机运行，macOS 和 Windows 可将 `qbittorrent.url` 设为 `http://host.docker.internal:1234`。

   `database_url` 是 SQLAlchemy 异步数据库连接 URL，默认值为 `sqlite+aiosqlite:///./data/mutsumi.db`；Docker 中对应 `/app/data/mutsumi.db`，首次启动会自动创建 SQLite 文件。也可改为其他 SQLAlchemy 异步驱动支持的数据库 URL，例如 PostgreSQL 的 `postgresql+asyncpg://用户名:密码@主机:5432/数据库`。`storage.data_path` 是 Mutsumi Server 容器内用于统计动画文件夹大小的路径，Docker 默认使用 `./data`（即 `/app/data`）；`qbittorrent.download_path` 是传给 qBittorrent 的保存路径，两者可因独立部署或挂载路径不同而分别配置。

3. 构建并在后台启动：

   ```bash
   docker compose up -d --build
   ```

4. 查看运行状态：

   ```bash
   docker compose ps
   docker compose logs -f server
   ```

服务默认监听 `http://localhost:12091`，健康检查地址为 `http://localhost:12091/api/v1/health`。

`compose.yaml` 将 `./data`、`./logs` 和运行配置绑定挂载到容器。默认 SQLite 数据库与下载数据均保存在 `./data` 中；使用其他数据库时，请自行提供对应数据库服务与连接 URL。启用 TLS 时，请在 `config.yaml` 中使用容器内的证书路径，并额外挂载对应证书与私钥文件。

## 服务端更新

在 `config.yaml` 的 `updates.repository` 配置 GitHub 仓库。管理员可在客户端选择正式 Release、Pre-release 或 `main` 分支检查更新。Release 与 Pre-release 必须提供 `mutsumi-server-{tag}.zip` 和同名 `.sha256` 文件；ZIP 包含服务端发布文件，但更新器只会原子替换 `app/`、`run.py`、`pyproject.toml`、`uv.lock` 与 `.python-version`，然后重启服务。

Docker 部署通过源码挂载运行，更新后容器内的启动脚本会重新同步依赖并拉起 Python 进程。本机部署也应使用 `./start.sh`，以便更新后的服务自动重启。`config.yaml`、`data/`、`logs/`、证书、`compose.yaml`、`Dockerfile` 和 `start.sh` 不会被更新包覆盖。
