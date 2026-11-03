#!/usr/bin/env bash
# =============================================================
#  LNMP 代码每日备份
#  配合 mysql_backup.sh + notify.sh，凑成「代码 + 数据库」完整备份
#  crontab: 30 3 * * * /opt/ops/project2-lnmp/scripts/code_backup.sh >> /opt/ops/logs/scripts/code-backup-cron.log 2>&1
# =============================================================
set -uo pipefail

APP_DIR="${APP_DIR:-/opt/ops/project2-lnmp/app}"
BACKUP_DIR="${BACKUP_DIR:-/opt/ops/backup/code}"
LOG_FILE="${LOG_FILE:-/opt/ops/logs/scripts/code-backup.log}"
KEEP_DAYS="${KEEP_DAYS:-7}"
NOTIFY="$(cd "$(dirname "$0")/.." && pwd)/notify.sh"

DATE=$(date '+%Y%m%d_%H%M%S')
mkdir -p "$BACKUP_DIR" "$(dirname "$LOG_FILE")"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"; }

log "=========================================="
log "代码备份开始: ${APP_DIR}"

if [[ ! -d "$APP_DIR" ]]; then
    log "[ERROR] 代码目录不存在: ${APP_DIR}"
    bash "$NOTIFY" "代码备份失败" "目录不存在: ${APP_DIR}" critical 2>/dev/null
    exit 1
fi

FAILED=0
OUT=""

# ---------------- 1. 备份（git 仓库用 bundle，普通目录用 tar）----------------
if [[ -d "${APP_DIR}/.git" ]]; then
    # git bundle：单文件包含全部提交历史，恢复时 git clone xxx.bundle 即可
    OUT="${BACKUP_DIR}/code_${DATE}.bundle"
    log "[1/2] git bundle -> ${OUT}"
    if git -C "$APP_DIR" bundle create "$OUT" --all 2>>"$LOG_FILE"; then
        log "      完成: $(du -h "$OUT" | cut -f1)"
    else
        log "[ERROR] git bundle 失败"; FAILED=1
    fi
else
    # 普通目录：tar 打包，排除可重建/体积大的内容
    OUT="${BACKUP_DIR}/code_${DATE}.tar.gz"
    log "[1/2] tar 打包 -> ${OUT}"
    if tar czf "$OUT" -C "$(dirname "$APP_DIR")" \
            --exclude='*/node_modules' --exclude='*/.git' \
            --exclude='*.log' --exclude='*/runtime' --exclude='*/cache' \
            "$(basename "$APP_DIR")" 2>>"$LOG_FILE"; then
        log "      完成: $(du -h "$OUT" | cut -f1)"
    else
        log "[ERROR] tar 打包失败"; FAILED=1
    fi
fi

# ---------------- 2. 校验：文件必须存在且非空 ----------------
[[ -s "$OUT" ]] || { log "[ERROR] 备份文件为空或不存在: ${OUT}"; FAILED=1; }
if [[ $FAILED -eq 0 && "${OUT##*.}" == "gz" ]]; then
    gzip -t "$OUT" || { log "[ERROR] tar.gz 完整性校验失败"; FAILED=1; }
fi

# ---------------- 3. 清理 N 天前 ----------------
log "[2/2] 清理 ${KEEP_DAYS} 天前备份"
DEL=$(find "$BACKUP_DIR" \( -name '*.bundle' -o -name '*.tar.gz' \) -mtime +"$KEEP_DAYS" -print -delete 2>/dev/null | wc -l)
log "      删除 ${DEL} 个，剩余 $(find "$BACKUP_DIR" \( -name '*.bundle' -o -name '*.tar.gz' \) | wc -l) 个"

# ---------------- 4. 输出状态 ----------------
log "------------------------------------------"
if [[ $FAILED -eq 0 ]]; then
    log "[SUCCESS] 代码备份完成 | 文件: ${OUT} ($(du -h "$OUT" | cut -f1))"
    log "STATUS=OK FILE=${OUT}"
    exit 0
else
    log "[FAILED] 代码备份存在失败项"
    log "STATUS=FAILED"
    bash "$NOTIFY" "代码备份失败" "目录 ${APP_DIR} 备份异常，检查 ${LOG_FILE}" critical 2>/dev/null
    exit 1
fi
