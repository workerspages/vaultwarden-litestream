# vaultwarden - S3 数据持久化版 (Litestream 实时备份 + Rclone 混合架构)

基于 vaultwarden 官方镜像，采用最新的“**SQLite + Litestream** 流式实时备份”搭配“**Rclone** 静态资源增量备份”形成**混合双备份安全架构**。

特别适用于没有持久化存储卷的云服务、PaaS 平台（如 Render, Fly.io, Zeabur 等）。结果是：就算所在的机房崩溃，您的数据库不但能秒级异地备份，用户上传的附件、系统配置以及安全密钥也完好无损地躺在 S3/R2 当中等待恢复。

本项目默认开启了双架构（`linux/amd64`, `linux/arm64`）支持。

## 💡 工作原理

```text
容器启动 → 
  ├─ S3 恢复最新数据库 db.sqlite (Litestream 处理)
  └─ S3 恢复附件、配置等静态文件 (Rclone 处理)
→ 启动 vaultwarden 服务进程
→ 进入后台双线容灾模式:
  ├─ 只要用户写入记录，实时向 S3 抄送库指令流 (Litestream)
  └─ 如果有文件上传，每分钟级将新增的附件和发送项目步进同步 (Rclone)
```

1. **核心库实时保护**: Litestream 利用 WAL 层机制将核心密码账本变动毫秒级向远方推流。绝不丢失数据。
2. **附加生态定时同步**: 激活 `SYNC_STATIC_FILES=true` 之后，系统将建立轻量独立脚本，通过 `Rclone` 把剩下的附件等零散文件增量发送归档，形成全面的数据保护网。

## ⚙️ 环境变量设置

您只需要分配一套基本的 S3 凭据即可，系统在后台会自动重定向让相关的引擎复用这套凭据。

| 变量名 | 必填 | 说明 | 默认值 |
|--------|------|------|--------|
| `LITESTREAM_ENDPOINT` | ✅ | S3/R2 兼容的端点 URL（如 Cloudflare R2 或 AWS 端点） | - |
| `LITESTREAM_ACCESS_KEY_ID` | ✅ | Access Key Id | - |
| `LITESTREAM_SECRET_ACCESS_KEY` | ✅ | Secret Access Key | - |
| `LITESTREAM_BUCKET` | ✅ | 存储桶名称 | - |
| `LITESTREAM_REGION` | ❌ | 存储区域 | `us-east-1` |
| `LITESTREAM_PATH` | ❌ | 桶内存储 SQLite DB 文件路径 | `vaultwarden/db.sqlite3` |
| `SYNC_STATIC_FILES` | ❌ | **是否开启混合备份附带存储诸如上传的附件、系统密钥等** | `false`|
| `SYNC_INTERVAL` | ❌ | 静态文件备份循环频次 (分钟) | `5` |
| `STATIC_BACKUP_PATH`| ❌ | 静态群组在桶内统一存放对应的子路径名称 | `vaultwarden/data_files` |

> ⚠️ 注意1：原版 Rclone 方案已被剔除，如果需要迁移历史数据，必须先手动下载并在本地通过 Litestream 或直接存入正确的 DB 位置再上传到新的桶位置。
> ⚠️ 注意2：本镜像去除了对文件内容的额外打包加密逻辑以提高轻量化和稳定性。在传输中始终使用 TLS（HTTPS）；在静止状态，强烈建议利用你的 S3 网盘提供商设置 Server-Side Encryption (SSE)。

## 🚀 部署指南 (针对无状态 PaaS)

在类似 Render、Fly.io、Koyeb 等 PaaS 平台部署极其简单：

1. **镜像拉取**: 指定镜像为 `ghcr.io/workerspages/vaultwarden-litestream:latest` 或 `docker.io/workerspages/vaultwarden-litestream:latest`。
2. **端口设置**: 容器默认通过 Cloudflare 兼容的 HTTP 端口暴露服务：**`8080`**。
3. **注入变量**: 填补上述的环境变量表，依据您使用的存储方案分配 S3 密钥信息。
4. **启动服务**: 容器将会在拉取云端数据后自动在 `8080` 端口开启 Vaultwarden 服务。

## 🛠️ GitHub Actions 与自动构建生态

如果您自己 Fork 此项目，该程序已经自带了一套完整的全自动发布工作流（位于 `.github/workflows/docker-build.yml`）。

当您修改程序代码并 Push 后，系统会自动使用 `Docker Buildx` 编译多平台并发版（涵盖 `linux/amd64` 和 `linux/arm64`）：
- **默认推送**：会自动推送至 GitHub 原生源 `ghcr.io`。
- **Docker Hub 同步（可选）**：如需同步发布到 Docker Hub，请在 Fork 的仓库 `Settings -> Secrets and variables -> Actions` 中，补充设定 `DOCKERHUB_USERNAME` 以及 `DOCKERHUB_TOKEN` 凭证。系统感知相关 Secrets 存在时会自动启用同步推送！
