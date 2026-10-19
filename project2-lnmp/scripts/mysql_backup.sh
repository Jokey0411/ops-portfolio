#!/usr/bin/env bash
# =============================================================
#  LNMP MySQL 每日备份
#  简历对应：「编写 Shell 脚本实现 MySQL 每日定时备份，
#             自动保留 7 天数据并输出日志状态」
#  crontab: 0 3 * * * /opt/ops/project2-lnmp/scripts/mysql_backup.sh >> /opt/ops/logs/scripts/lnmp-backup-cron.log 2>&1
# =============================================================
set -uo pipefail

CONTAINER="${CONTAINER:-lnmp-mysql}"
BACKUP_DIR="${BACKUP_DIR:-/opt/ops/backup/mysql}"
LOG_FILE="${LOG_FILE:-/opt/ops/logs/scripts/lnmp-backup.log}"
KEEP_DAYS="${KEEP_DAYS:-7}"
MYSQL_USER="root"
MYSQL_PASS="Root@123456"
DATE=$(date '+%Y%m%d_%H%M%S')
DAY=$(date '+%Y%m%d')

mkdir -p "$BACKUP_DIR" "$(dirname "$LOG_FILE")"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"; }

log "=========================================="
log "MySQL 备份开始 (容器: ${CONTAINER})"

START=$(date +%s)
FAILED=0

# ---------------- 1. 获取数据库列表 ----------------
DBS=$(docker exec -e MYSQL_PWD="$MYSQL_PASS" "$CONTAINER" mysql -u"$MYSQL_USER" -N -B -e \
      "SELECT schema_name FROM information_schema.schemata
       WHERE schema_name NOT IN ('information_schema','performance_schema','sys','mysql');" 2>/dev/null)

if [[ -z "$DBS" ]]; then
    log "[ERROR] 无法获取数据库列表，容器可能未运行"
    bash "$(dirname "$0")/../notify.sh" "LNMP备份失败" "无法连接 MySQL 容器 ${CONTAINER}" critical 2>/dev/null
    exit 1
fi
log "待备份数据库: $(echo $DBS | tr '\n' ' ')"

# ---------------- 2. 全库备份 ----------------
FULL="${BACKUP_DIR}/full_${DAY}_${DATE}.sql"
log "[1/3] 全库备份 -> ${FULL}.gz"
if docker exec -e MYSQL_PWD="$MYSQL_PASS" "$CONTAINER" mysqldump -u"$MYSQL_USER" \
        --single-transaction --quick --routines --triggers --events \
        --set-gtid-purged=OFF --all-databases > "$FULL" 2>>"$LOG_FILE"; then
    gzip -f "$FULL"
    SIZE=$(du -m "${FULL}.gz" | cut -f1)
    log "      完成: ${FULL}.gz  (${SIZE} MB)"
    gzip -t "${FULL}.gz" || { log "[ERROR] 备份文件损坏"; FAILED=1; }
else
    log "[ERROR] 全库备份失败"; FAILED=1
fi

# ---------------- 3. 按库单独备份（便于单库恢复）----------------
log "[2/3] 分库备份"
for db in $DBS; do
    F="${BACKUP_DIR}/${db}_${DAY}_${DATE}.sql"
    if docker exec -e MYSQL_PWD="$MYSQL_PASS" "$CONTAINER" mysqldump -u"$MYSQL_USER" \
            --single-transaction --quick --routines --triggers \
            --set-gtid-purged=OFF "$db" > "$F" 2>>"$LOG_FILE"; then
        gzip -f "$F"
        log "      ${db}: $(du -m "${F}.gz" | cut -f1) MB"
    else
        log "      [ERROR] ${db} 备份失败"; FAILED=1
    fi
done

# ---------------- 4. 清理 7 天前 ----------------
log "[3/3] 清理 ${KEEP_DAYS} 天前备份"
DEL=$(find "$BACKUP_DIR" -name '*.sql.gz' -mtime +${KEEP_DAYS} -print -delete 2>/dev/null | wc -l)
log "      删除 ${DEL} 个，剩余 $(find "$BACKUP_DIR" -name '*.sql.gz' | wc -l) 个"

END=$(date +%s)
COST=$((END - START))

# ---------------- 5. 输出状态 ----------------
log "------------------------------------------"
if [[ $FAILED -eq 0 ]]; then
    log "[SUCCESS] 备份完成 | 耗时 ${COST}s | 总计占用 $(du -sm "$BACKUP_DIR" | cut -f1) MB"
    log "备份清单:"
    ls -lht "$BACKUP_DIR" | head -8 | while read -r l; do log "  $l"; done
    # 状态行（便于外部 grep 监控）
    log "STATUS=OK COST=${COST}s DIRS=${BACKUP_DIR}"
    exit 0
else
    log "[FAILED] 备份存在失败项，耗时 ${COST}s"
    log "STATUS=FAILED COST=${COST}s"
    bash "$(dirname "$0")/../notify.sh" "❗LNMP MySQL 备份失败" \
         "容器 ${CONTAINER} 备份异常，检查 ${LOG_FILE}" critical 2>/dev/null
    exit 1
fi
