#!/usr/bin/env bash
# =============================================================
#  备份心跳检测（兜底「静默失败」）
#  为什么需要：脚本失败会告警，但如果 cron 没生效、机器挂过、脚本根本没跑，
#  就不会有任何告警。这里检查「最新备份文件的年龄」，超阈值即告警。
#  crontab: 0 9 * * * /opt/ops/project2-lnmp/scripts/backup_heartbeat.sh >> /opt/ops/logs/scripts/backup-heartbeat.log 2>&1
# =============================================================
set -uo pipefail

BACKUP_ROOT="${BACKUP_ROOT:-/opt/ops/backup}"
MAX_AGE_HOURS="${MAX_AGE_HOURS:-26}"
LOG_FILE="${LOG_FILE:-/opt/ops/logs/scripts/backup-heartbeat.log}"
NOTIFY="$(cd "$(dirname "$0")/.." && pwd)/notify.sh"

mkdir -p "$(dirname "$LOG_FILE")"
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"; }

log "=========================================="
log "备份心跳检测开始 (阈值 ${MAX_AGE_HOURS}h)"

FAILED=0

check() {
    local dir="$1" name="$2"
    local newest ts path age_h
    newest=$(find "$dir" -type f \( -name '*.sql.gz' -o -name '*.bundle' -o -name '*.tar.gz' \) \
             -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1)

    if [[ -z "$newest" ]]; then
        log "[ERROR] ${name}（${dir}）没有任何备份文件"
        bash "$NOTIFY" "备份缺失告警" "${name} 目录无任何备份文件" critical 2>/dev/null
        FAILED=1
        return
    fi

    ts=$(echo "$newest" | awk '{print $1}' | cut -d. -f1)
    path=$(echo "$newest" | awk '{print $2}')
    age_h=$(( ( $(date +%s) - ts ) / 3600 ))

    log "${name} 最新: ${path}（${age_h}h 前）"

    if [[ $age_h -gt $MAX_AGE_HOURS ]]; then
        log "[ERROR] ${name} 已 ${age_h}h 未更新，超过阈值 ${MAX_AGE_HOURS}h"
        bash "$NOTIFY" "备份超时告警" "${name} 已 ${age_h}h 未更新，疑似任务未执行" critical 2>/dev/null
        FAILED=1
    fi
}

check "${BACKUP_ROOT}/mysql" "MySQL备份"
check "${BACKUP_ROOT}/code"  "代码备份"

log "------------------------------------------"
if [[ $FAILED -eq 0 ]]; then
    log "[SUCCESS] 心跳正常，两类备份均在 ${MAX_AGE_HOURS}h 内更新"
    exit 0
else
    log "[FAILED] 心跳异常，已触发告警"
    exit 1
fi
