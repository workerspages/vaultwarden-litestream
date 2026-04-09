# vaultwarden - S3 数据持久化版 (Litestream 实时备份)

基于 vaultwarden 官方镜像，采用最新的“SQLite + Litestream S3 实时备份”方案。配置 Litestream，让它持续将 `db.sqlite3` 的状态流式同步备份到 Cloudflare R2 或 AWS S3 对象存储中。

特别适用于没有持久化存储卷的云服务、PaaS 平台（如 Render, Fly.io, Zeabur 等）。结果是：就算所在的机房崩溃，你的数据库依然完好无损地躺在 S3/R2 里，随时能够轻松恢复。

本项目默认开启了双架构（`linux/amd64`, `linux/arm64`）支持。

## 💡 工作原理

```text
容器启动 → 从 S3 恢复最新数据库 → 启动 vaultwarden 服务 + Litestream 后台实时将数据流复制到 S3
```

1. **启动时恢复**: 容器启动阶段，先执行 `litestream restore` 检查 S3 中是否有备份，如有则拉取并恢复到本地。
2. **实时备份**: 随后启动主服务，同时作为 `litestream replicate` 的子进程运行。只要本地 SQLite 发出写变更，改动会在几秒钟内反映到远端对象存储中。

## ⚙️ 环境变量设置

Litestream 需要通过以下环境变量定位并授权访问您的 S3/R2 存储桶。

| 变量名 | 必填 | 说明 | 默认值 |
|--------|------|------|--------|
| `LITESTREAM_ENDPOINT` | ✅ | S3/R2 兼容的端点 URL（如 Cloudflare R2 或 AWS 端点） | - |
| `LITESTREAM_ACCESS_KEY_ID` | ✅ | Access Key Id | - |
| `LITESTREAM_SECRET_ACCESS_KEY` | ✅ | Secret Access Key | - |
| `LITESTREAM_BUCKET` | ✅ | 存储桶名称 | - |
| `LITESTREAM_REGION` | ❌ | 存储区域 | `us-east-1` |
| `LITESTREAM_PATH` | ❌ | 桶内存储文件路径 | `vaultwarden/db.sqlite3` |

> ⚠️ 注意1：原版 Rclone 方案已被剔除，如果需要迁移历史数据，必须先手动下载并在本地通过 Litestream 或直接存入正确的 DB 位置再上传到新的桶位置。
> ⚠️ 注意2：本镜像去除了对文件内容的额外打包加密逻辑以提高轻量化和稳定性。在传输中始终使用 TLS（HTTPS）；在静止状态，强烈建议利用你的 S3 网盘提供商设置 Server-Side Encryption (SSE)。

## 🚀 部署指南 (针对无状态 PaaS)

在类似 Render、Fly.io、Koyeb 等 PaaS 平台部署极其简单：

1. **镜像拉取**: 指定镜像为 `ghcr.io/workerspages/vaultwarden-oss:latest` 或 `docker.io/workerspages/vaultwarden-oss:latest`。
2. **端口设置**: 容器默认通过 Cloudflare 兼容的 HTTP 端口暴露服务：**`8080`**。
3. **注入变量**: 填补上述的环境变量表，依据您使用的存储方案分配 S3 密钥信息。
4. **启动服务**: 容器将会在拉取云端数据后自动在 `8080` 端口开启 Vaultwarden 服务。

## 🛠️ GitHub Actions 与自动构建生态

如果您自己 Fork 此项目，该程序已经自带了一套完整的全自动发布工作流（位于 `.github/workflows/docker-build.yml`）。

当您修改程序代码并 Push 后，系统会自动使用 `Docker Buildx` 编译多平台并发版（涵盖 `linux/amd64` 和 `linux/arm64`）：
- **默认推送**：会自动推送至 GitHub 原生源 `ghcr.io`。
- **Docker Hub 同步（可选）**：如需同步发布到 Docker Hub，请在 Fork 的仓库 `Settings -> Secrets and variables -> Actions` 中，补充设定 `DOCKERHUB_USERNAME` 以及 `DOCKERHUB_TOKEN` 凭证。系统感知相关 Secrets 存在时会自动启用同步推送！
