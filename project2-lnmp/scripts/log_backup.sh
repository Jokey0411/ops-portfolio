#!/usr/bin/env bash
# =============================================================
#  日志按日期归档备份（默认收最近 7 天改动过的日志）
#
#  做法：找 SRC_DIRS 下 7 天内修改过的日志 → 复制到临时目录
#        （内部保留原目录结构，文件名追加该文件的日期）
#        → 打包成 logs_YYYY-MM-DD.tar.gz → 校验 → 清理过期包
#
#  特点：不删源文件、不移动、跳过正在写的文件、可 DRY_RUN 预演
#
#  用法：
#    bash log_backup.sh                 # 正常跑
#    DRY_RUN=1 bash log_backup.sh       # 只列出会备份哪些文件，不落盘
#    DAY_WINDOW=30 bash log_backup.sh   # 改成收最近 30 天
#
#  crontab（每周一 04:00，和 03:00 的库备份错开）：
#    0 4 * * 1 /opt/ops/project2-lnmp/scripts/log_backup.sh >> /opt/ops/logs/scripts/log-backup-cron.log 2>&1
# =============================================================
set -uo pipefail

# ---------------- 可调参数（都能用环境变量覆盖） ----------------
SRC_DIRS="${SRC_DIRS:-/opt/ops/project2-lnmp/logs}"   # 多个目录用空格分隔
BACKUP_DIR="${BACKUP_DIR:-/opt/ops/backup/logs}"
LOG_FILE="${LOG_FILE:-/opt/ops/logs/scripts/log-backup.log}"
DAY_WINDOW="${DAY_WINDOW:-7}"        # ★ 时间窗口：最近 7 天
MIN_AGE_MIN="${MIN_AGE_MIN:-5}"      # 跳过 N 分钟内还在写的文件（避免抓到半截）
KEEP_DAYS="${KEEP_DAYS:-30}"         # 备份包保留 30 天
FILE_PATTERN="${FILE_PATTERN:-*.log *.log.* *.gz}"   # 收哪些文件
DRY_RUN="${DRY_RUN:-0}"

# ★ 注意：notify.sh 就在本脚本同级目录，不要写 dirname/..
NOTIFY="$(cd "$(dirname "$0")" && pwd)/notify.sh"

STAMP="$(date '+%Y-%m-%d')"          # ★ 备份包的日期名
OUT="${BACKUP_DIR}/logs_${STAMP}.tar.gz"
LIST="${BACKUP_DIR}/logs_${STAMP}.list"

mkdir -p "$BACKUP_DIR" "$(dirname "$LOG_FILE")"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"; }

# ---------------- 防重叠：上一轮没跑完就直接退出 ----------------
if command -v flock >/dev/null 2>&1; then
    exec 9>"${BACKUP_DIR}/.log_backup.lock"
    if ! flock -n 9; then
        log "[SKIP] 上一轮备份还在跑，本轮跳过"
        exit 0
    fi
else
    log "[WARN] 没有 flock（util-linux），跳过防重叠保护"
fi

# ---------------- 临时工作目录，退出时自动清理 ----------------
TMP="$(mktemp -d "${BACKUP_DIR}/.tmp.${STAMP}.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

log "=========================================="
log "日志归档开始 | 窗口=${DAY_WINDOW}天 | 源=${SRC_DIRS}"

# ---------------- 1. 检查源目录 ----------------
ALIVE=0
for d in $SRC_DIRS; do
    [[ -d "$d" ]] && ALIVE=1
done
if [[ $ALIVE -eq 0 ]]; then
    log "[ERROR] 所有源目录都不存在: ${SRC_DIRS}"
    [[ -x "$NOTIFY" ]] && bash "$NOTIFY" "日志备份失败" "源目录不存在: ${SRC_DIRS}" critical 2>/dev/null
    exit 1
fi

# ---------------- 2. 收集文件 ----------------
# -newermt "-7 days"：按修改时间筛，比按文件名可靠（文件名不一定带日期）
# -mmin +5：至少 5 分钟没改动过，跳过正在写的活跃日志
FIND_NAME=()
for p in $FILE_PATTERN; do
    if [[ ${#FIND_NAME[@]} -gt 0 ]]; then FIND_NAME+=(-o); fi
    FIND_NAME+=(-name "$p")
done

COUNT=0
TOTAL_BYTES=0
> "$TMP/.manifest"

for d in $SRC_DIRS; do
    [[ -d "$d" ]] || { log "[WARN] 跳过不存在的目录: $d"; continue; }

    while IFS= read -r -d '' f; do
        rel="${f#"$d"/}"                            # 相对路径，避免同名文件互覆盖
        dtag="$(date -r "$f" '+%Y-%m-%d')"          # ★ 取这个文件自己的日期
        dst_dir="${TMP}/$(basename "$d")/$(dirname "$rel")"
        dst="${dst_dir}/${rel##*/}.${dtag}"         # access.log → access.log.2026-11-07
        mkdir -p "$dst_dir"

        size=$(stat -c '%s' "$f" 2>/dev/null || echo 0)
        printf '%s\t%s\t%s\n' "$f" "$dtag" "$size" >> "$TMP/.manifest"
        COUNT=$((COUNT + 1))
        TOTAL_BYTES=$((TOTAL_BYTES + size))

        if [[ "$DRY_RUN" == "1" ]]; then
            log "[DRY] $f  ->  ${rel##*/}.${dtag}  (${size}B)"
        else
            cp -p "$f" "$dst" 2>>"$LOG_FILE" || log "[WARN] 复制失败: $f"
        fi
    done < <(find "$d" -type f \( "${FIND_NAME[@]}" \) \
                  -newermt "-${DAY_WINDOW} days" -mmin +"$MIN_AGE_MIN" -print0 2>/dev/null)
done

log "命中文件: ${COUNT} 个，合计 $(numfmt --to=iec "$TOTAL_BYTES" 2>/dev/null || echo "${TOTAL_BYTES}B")"

if [[ "$COUNT" -eq 0 ]]; then
    log "[WARN] ${DAY_WINDOW} 天内没有可备份的日志，未生成空包"
    exit 0
fi

if [[ "$DRY_RUN" == "1" ]]; then
    log "[DRY] 预演结束，未写任何备份文件"
    exit 0
fi

# ---------------- 3. 打包（包名带日期） ----------------
cp "$TMP/.manifest" "$LIST"
if tar -czf "$OUT" -C "$TMP" --exclude='./.manifest' --warning=no-file-changed . 2>>"$LOG_FILE"; then
    log "打包完成: ${OUT} ($(du -h "$OUT" | cut -f1))"
else
    log "[ERROR] tar 打包失败"
    [[ -x "$NOTIFY" ]] && bash "$NOTIFY" "日志备份失败" "tar 失败: ${OUT}" critical 2>/dev/null
    exit 1
fi

# ---------------- 4. 校验（空包/坏包比没备份更危险） ----------------
if [[ ! -s "$OUT" ]]; then
    log "[ERROR] 备份包为空: ${OUT}"; exit 1
fi
if ! gzip -t "$OUT" 2>/dev/null; then
    log "[ERROR] 备份包损坏（gzip -t 失败）: ${OUT}"
    [[ -x "$NOTIFY" ]] && bash "$NOTIFY" "日志备份失败" "包损坏: ${OUT}" critical 2>/dev/null
    exit 1
fi
log "校验通过: gzip -t OK，内含 $(tar -tzf "$OUT" | grep -c -v '/$') 个文件"

# ---------------- 5. 清理过期备份 ----------------
DEL=$(find "$BACKUP_DIR" -maxdepth 1 -type f \
        \( -name 'logs_*.tar.gz' -o -name 'logs_*.list' \) \
        -mtime +"$KEEP_DAYS" -print -delete 2>/dev/null | wc -l)
[[ "$DEL" -gt 0 ]] && log "清理 ${KEEP_DAYS} 天前的旧备份: ${DEL} 个文件"

log "日志归档完成 | 包=${OUT} | 清单=${LIST}"
log "=========================================="
exit 0
