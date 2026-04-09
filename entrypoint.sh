#!/bin/bash
set -e

echo "[Init] Starting Vaultwarden with Litestream & Rclone (Hybrid Mode)..."

# 检查是否配置了必要参数
if [ -z "$LITESTREAM_BUCKET" ] || [ -z "$LITESTREAM_ENDPOINT" ]; then
    echo "[Init] Warning: LITESTREAM_BUCKET or LITESTREAM_ENDPOINT is not set. Running Vaultwarden without replication."
    if [ -x /start.sh ]; then
        exec /start.sh "$@"
    else
        exec vaultwarden "$@"
    fi
    exit 0
fi

# ================= Rclone 静态文件隔离配置 =================
if [ "$SYNC_STATIC_FILES" = "true" ]; then
    echo "[Init] Configuring Rclone for static files..."
    mkdir -p /root/.config/rclone
    cat > /root/.config/rclone/rclone.conf <<EOF
[s3]
type = s3
provider = Other
env_auth = false
access_key_id = ${LITESTREAM_ACCESS_KEY_ID}
secret_access_key = ${LITESTREAM_SECRET_ACCESS_KEY}
endpoint = ${LITESTREAM_ENDPOINT}
region = ${LITESTREAM_REGION:-us-east-1}
EOF
    RCLONE_TARGET="s3:${LITESTREAM_BUCKET}/${STATIC_BACKUP_PATH:-vaultwarden/data_files}"
    
    echo "[Init] Restoring static files from remote: ${RCLONE_TARGET} to /data/ (excluding db!)"
    rclone copy "${RCLONE_TARGET}" /data/ --exclude "db.sqlite3*" -v || echo "[Init] Warn: First run or remote static files empty. Skipping."

    # 生成常驻后台脚本
    INTERVAL=${SYNC_INTERVAL:-5}
    cat > /sync.sh <<EOF
#!/bin/bash
while true; do
    sleep \$(( ${INTERVAL} * 60 ))
    echo "[\$(date)] Auto-syncing static files from /data/ to ${RCLONE_TARGET}..."
    rclone sync /data/ "${RCLONE_TARGET}" --exclude "db.sqlite3*" -v
done
EOF
    chmod +x /sync.sh
    echo "[Init] Starting background sync process for static files (Interval: ${INTERVAL}m)..."
    /sync.sh &
fi

# ================= Litestream 恢复与启动 =================
echo "[Init] Restoring database from remote S3 via Litestream..."
# 使用 -if-replica-exists 表示如果远端没有备份，就不作任何操作（适用于首次启动）
if litestream restore -if-replica-exists /data/db.sqlite3; then
    echo "[Init] Restore process completed."
else
    echo "[Init] Warning: Restore failed. Please check your credentials or network."
fi

# 启动同步与主程序
echo "[Init] Starting Litestream replication..."
if [ -x /start.sh ]; then
    EXEC_CMD="/start.sh $*"
else
    EXEC_CMD="vaultwarden $*"
fi

exec litestream replicate -exec "$EXEC_CMD"
