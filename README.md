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

## 📦 旧数据无损上云 (迁移导入指南)

如果您有一个完整的旧版 Vaultwarden 备份文件夹（包含 `db.sqlite3` 数据库和 `attachments` 附件），您可以发挥“混合架构”的双驱优势，通过**在您的个人电脑本地运行一次临时过渡 Docker** 来实现一键全部同步进云。

**第 1 步：准备本地旧数据**
将您以前备份的 `db.sqlite3` 及其附属资源统统放在同一个本地文件夹里。比如：`/Users/xxx/old_vaultwarden_data`

**第 2 步：跑一次本地临时容器给 S3"灌"数据**
在您包含 Docker 环境的终端中运行以下命令（请根据实际填入您的 S3 变量和实际在磁盘上的本机旧数据路径）：

```bash
docker run --rm -it \
  -v /Users/xxx/old_vaultwarden_data:/data \
  -e LITESTREAM_ENDPOINT="https://s3.example.com" \
  -e LITESTREAM_ACCESS_KEY_ID="your_access_key" \
  -e LITESTREAM_SECRET_ACCESS_KEY="your_secret_key" \
  -e LITESTREAM_BUCKET="your_bucket_name" \
  -e SYNC_STATIC_FILES="true" \
  ghcr.io/workerspages/vaultwarden-litestream:latest
```

**发生了什么？**
1. 容器初次开机检测到 `/data` 里已经有 `db.sqlite3` 和文件，会跳过执行覆盖。
2. 内部的 **Litestream** 发现本地库比 S3 的新，会在几秒内将其切分包装成流式副本并打包装入云端 Bucket！
3. 分流执行的 **Rclone** 也会把剩余的那些附件直接上传。这个进程中您的混合云配置已被彻底构建完毕。
4. 在观察日志输出流大致一两分钟后，即可使用 `Ctrl + C` 结束并强制停止这台本地一次性容器。

**第 3 步：去 PaaS 云平台坐享其成**
S3 中已有标准的架构源。这时用前文讲述的“部署指南”，在您的 Render / Fly.io 平台开出空白容器并套用同套变量。PaaS 在第一次开机时会反向倒带把云端的全部东西自动下载回 `/data/`。
此时直接打开网页，您就会发现什么都没有丢失，历史记录无缝在公网上复活了！

## 🔓 随时安全撤出 (脱离本库完美兼容官方原版)

我们这个项目（即这套备份架构）**没有对您的数据进行任何私有化处理或“绑架”**。这套方案本质上是个极其负责任的“搬运保护工”，它运送的依然是官方最标准的货物格式。您可以随时无痛全盘撤除并拿回原生态纯数据，让官方原装版 Vaultwarden 完美接手：

### 1. 静态附件和密钥（Rclone 备份区）
我们在 S3 桶里的 `vaultwarden/data_files` 目录下看到的所有东西（图库图片、附件、`rsa_key`等），都是**以原样、明文（未加扰）的原始文件格式直接存储的。**
- **怎么取回并给原版用？** 直接在网页登录 S3 存储桶，或者用第三方云盘工具（例如 Cyberduck）把这些零散的文件下载回本地电脑，原封不动地塞进官方 `/data/` 目录中即可，原版 Vaultwarden 立刻就能完全识别并接管。

### 2. SQLite 核心密码库（Litestream 备份区）
由于 Litestream 负责打包流式同步，S3 里的表现形式是 `generations` 和 `wal` 日志切块，它无法进行直接的点击下载可用。
- **怎么取回并给原版用？** 只要您在任意有网的电脑（Windows、Mac 或 Linux）上安装一个百 KB 级别的官方 [Litestream 小工具](https://litestream.io/install/)，然后执行一次它最原生的还原命令：

  ```bash
  litestream restore -o /您的本地/指定的/db.sqlite3 s3://your_bucket_name/vaultwarden/db.sqlite3
  ```
  不到两秒钟，Litestream 就会自动把 S3 里的日志快照**重组成一个标准的、官方的 `db.sqlite3` 单体文件**下载到您的本机。这也是官方底层最纯正的结构，用官方原版容器挂载它，哪怕完全不用我们的镜像，绝对的百分之百兼容！

## 🛠️ GitHub Actions 与自动构建生态

如果您自己 Fork 此项目，该程序已经自带了一套完整的全自动发布工作流（位于 `.github/workflows/docker-build.yml`）。

当您修改程序代码并 Push 后，系统会自动使用 `Docker Buildx` 编译多平台并发版（涵盖 `linux/amd64` 和 `linux/arm64`）：
- **默认推送**：会自动推送至 GitHub 原生源 `ghcr.io`。
- **Docker Hub 同步（可选）**：如需同步发布到 Docker Hub，请在 Fork 的仓库 `Settings -> Secrets and variables -> Actions` 中，补充设定 `DOCKERHUB_USERNAME` 以及 `DOCKERHUB_TOKEN` 凭证。系统感知相关 Secrets 存在时会自动启用同步推送！
