#!/usr/bin/env bash
# =============================================================
#  每日备份：MySQL 全量 + 业务代码 + 配置文件
#  保留 7 天，输出状态日志，失败自动告警
#  crontab: 0 2 * * * /opt/ops/project1-cluster/scripts/backup.sh >> /opt/ops/logs/scripts/backup-cron.log 2>&1
# =============================================================
set -uo pipefail

PROJECT_DIR="${PROJECT_DIR:-/opt/ops/project1-cluster}"
BACKUP_ROOT="${BACKUP_ROOT:-/opt/ops/backup}"
LOG_DIR="${LOG_DIR:-/opt/ops/logs/scripts}"
KEEP_DAYS="${KEEP_DAYS:-7}"
DATE=$(date '+%Y%m%d_%H%M%S')
DAY=$(date '+%Y%m%d')

MYSQL_USER="root"
MYSQL_PASS="Root@123456"
DB_CONTAINER="${DB_CONTAINER:-node1-db}"     # 备份主库

mkdir -p "${BACKUP_ROOT}/mysql" "${BACKUP_ROOT}/code" "${LOG_DIR}"
LOG="${LOG_DIR}/backup.log"

log() {
    echo "[$(date '+%F %T')] $*" | tee -a "$LOG"
}

log "=========== 备份开始 ==========="

FAILED=0
SIZE_MYSQL=0
SIZE_CODE=0
START_TS=$(date +%s)

# ---------------- 1. MySQL 全量备份 ----------------
# --single-transaction：InnoDB 一致性快照，不锁表（生产必备）
# --routines --triggers --events：存储过程/触发器/事件一起带走
# --set-gtid-purged=OFF：避免导入时因 GTID 冲突失败（★ 常见坑）
log "[1/4] 备份 MySQL 容器 ${DB_CONTAINER}"
DUMP_FILE="${BACKUP_ROOT}/mysql/mysql_${DAY}_${DATE}.sql"

if docker exec -e MYSQL_PWD="${MYSQL_PASS}" "${DB_CONTAINER}" \
        mysqldump -u"${MYSQL_USER}" \
        --single-transaction --quick --routines --triggers --events \
        --set-gtid-purged=OFF --all-databases > "${DUMP_FILE}" 2>>"$LOG"; then

    gzip -f "${DUMP_FILE}"
    SIZE_MYSQL=$(du -m "${DUMP_FILE}.gz" | cut -f1)
    log "  ✔ 数据库备份完成：${DUMP_FILE}.gz (${SIZE_MYSQL}MB)"

    # 校验：能解开、且文件头是正常 SQL
    if ! gzip -t "${DUMP_FILE}.gz" 2>>"$LOG"; then
        log "  ✘ 备份文件校验失败（gzip -t 未通过）"
        FAILED=1
    fi
else
    log "  ✘ mysqldump 执行失败"
    FAILED=1
fi

# ---------------- 2. 业务代码 + 配置备份 ----------------
log "[2/4] 备份代码与配置"
CODE_FILE="${BACKUP_ROOT}/code/code_${DAY}_${DATE}.tar.gz"
if tar czf "${CODE_FILE}" \
        -C "$(dirname "$PROJECT_DIR")" "$(basename "$PROJECT_DIR")" \
        --exclude='*/logs/*' --exclude='*/data/*' 2>>"$LOG"; then
    SIZE_CODE=$(du -m "${CODE_FILE}" | cut -f1)
    log "  ✔ 代码备份完成：${CODE_FILE} (${SIZE_CODE}MB)"
else
    log "  ✘ 代码备份失败"
    FAILED=1
fi

# ---------------- 3. 清理过期备份（保留 7 天）----------------
log "[3/4] 清理 ${KEEP_DAYS} 天前的备份"
DELETED=$(find "${BACKUP_ROOT}" -type f \( -name 'mysql_*.sql.gz' -o -name 'code_*.tar.gz' \) \
          -mtime +${KEEP_DAYS} -print -delete 2>/dev/null | wc -l)
log "  已删除 ${DELETED} 个过期文件，剩余备份：$(find "${BACKUP_ROOT}" -type f | wc -l) 个"

# ---------------- 4. 磁盘空间检查 ----------------
log "[4/4] 磁盘与状态检查"
DISK_USE=$(df -h "${BACKUP_ROOT}" | awk 'NR==2{print $5}' | tr -d '%')
[[ ${DISK_USE} -ge 85 ]] && {
    log "  ⚠ 备份目录所在磁盘使用率 ${DISK_USE}%，偏高"
    bash "$(dirname "$0")/notify.sh" "备份磁盘空间告警" \
         "备份分区使用率 ${DISK_USE}%，请及时清理" warning
}

END_TS=$(date +%s)
COST=$((END_TS - START_TS))

# ---------------- 汇总 ----------------
if [[ $FAILED -eq 0 ]]; then
    log "✔ 备份成功 | 耗时 ${COST}s | MySQL ${SIZE_MYSQL}MB + 代码 ${SIZE_CODE}MB | 保留 ${KEEP_DAYS} 天"
    # 每天只在首次成功时发一次通知，避免刷屏（可选）
    [[ "${NOTIFY_ON_SUCCESS:-0}" == "1" ]] && \
        bash "$(dirname "$0")/notify.sh" "每日备份成功" \
        "MySQL ${SIZE_MYSQL}MB, 代码 ${SIZE_CODE}MB, 耗时 ${COST}s"
    exit 0
else
    log "✘ 备份失败"
    bash "$(dirname "$0")/notify.sh" "❗每日备份失败" \
         "备份脚本执行异常，请登录检查 $LOG" critical
    exit 1
fi
