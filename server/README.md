# Mutsumi Server

## Docker 部署

1. 在本目录创建运行配置：

   ```bash
   cp config.yaml.example config.yaml
   ```

2. 编辑 `config.yaml`，至少将 `auth.secret_key` 替换为安全的随机值；若 qBittorrent 在宿主机运行，macOS 和 Windows 可将 `qbittorrent.url` 设为 `http://host.docker.internal:1234`。

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

`compose.yaml` 使用命名卷持久化 SQLite 数据库、下载数据和日志。配置文件以只读方式挂载，不会被打入镜像；启用 TLS 时，请在 `config.yaml` 中使用容器内的证书路径，并额外挂载对应证书与私钥文件。
