#!/bin/bash
set -e

echo "[Init] Starting Vaultwarden with Litestream..."

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

# 从远端恢复数据
echo "[Init] Restoring data from remote S3..."
# 使用 -if-replica-exists 表示如果远端没有备份，就不作任何操作（适用于首次启动）
if litestream restore -if-replica-exists -v /data/db.sqlite3; then
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
