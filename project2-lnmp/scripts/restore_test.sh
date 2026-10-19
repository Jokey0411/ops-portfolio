#!/usr/bin/env bash
# =============================================================
#  备份恢复演练 —— 备份不验证等于没备份
#  ★ 这是面试官最爱的追问："你怎么确认备份是有效的？"
#  做法：起一个临时 MySQL 容器，把最新备份灌进去，校验数据行数
#  用法：bash scripts/restore_test.sh
# =============================================================
set -uo pipefail

BACKUP_DIR="${BACKUP_DIR:-/opt/ops/backup/mysql}"
TEST_CONTAINER="restore-test-$$"
TEST_PASS="Restore@123"
RESULT_LOG="${RESULT_LOG:-/opt/ops/logs/scripts/restore-test.log}"

mkdir -p "$(dirname "$RESULT_LOG")"
log() { echo "[$(date '+%F %T')] $*" | tee -a "$RESULT_LOG"; }

log "=========================================="
log "备份恢复演练开始"

# ---------------- 1. 找最新备份 ----------------
LATEST=$(ls -t "${BACKUP_DIR}"/full_*.sql.gz 2>/dev/null | head -1)
if [[ -z "$LATEST" ]]; then
    log "[ERROR] 未找到任何全量备份文件，先跑一次 mysql_backup.sh"
    exit 1
fi
log "使用备份文件: ${LATEST} ($(du -h "$LATEST" | cut -f1))"

# ---------------- 2. 起临时容器 ----------------
log "启动临时 MySQL 容器 ${TEST_CONTAINER} ..."
docker run -d --name "$TEST_CONTAINER" \
    -e MYSQL_ROOT_PASSWORD="$TEST_PASS" \
    -e MYSQL_ALLOW_EMPTY_PASSWORD=1 \
    --tmpfs /tmp \
    mysql:8.0 >/dev/null 2>&1

cleanup() {
    log "清理临时容器"
    docker rm -f "$TEST_CONTAINER" >/dev/null 2>&1
}
trap cleanup EXIT

# 等待就绪（MySQL 首次启动要 40~90 秒）
log "等待 MySQL 就绪..."
for i in $(seq 1 60); do
    if docker exec -e MYSQL_PWD="$TEST_PASS" "$TEST_CONTAINER" mysqladmin ping -uroot --silent &>/dev/null; then
        log "  MySQL 就绪（等待 $((i * 2)) 秒）"
        break
    fi
    sleep 2
done

# ---------------- 3. 恢复 ----------------
log "开始恢复..."
START=$(date +%s)
if zcat "$LATEST" | docker exec -i -e MYSQL_PWD="$TEST_PASS" "$TEST_CONTAINER" \
        mysql -uroot --force 2>&1 | grep -v '^$' | head -10; then
    :
fi
END=$(date +%s)
log "恢复完成，耗时 $((END - START))s"

# ---------------- 4. 校验 ----------------
log "数据校验："
docker exec -e MYSQL_PWD="$TEST_PASS" "$TEST_CONTAINER" mysql -uroot -e \
  "SELECT table_schema, table_name, table_rows
   FROM information_schema.tables
   WHERE table_schema NOT IN ('information_schema','performance_schema','sys','mysql')
   ORDER BY table_schema, table_name;" 2>/dev/null

# 拿生产库的行数做对比
PROD_COUNT=$(docker exec -e MYSQL_PWD="Root@123456" lnmp-mysql mysql -uroot -N -B -e \
  "SELECT COUNT(*) FROM shop.orders;" 2>/dev/null)
TEST_COUNT=$(docker exec -e MYSQL_PWD="$TEST_PASS" "$TEST_CONTAINER" mysql -uroot -N -B -e \
  "SELECT COUNT(*) FROM shop.orders;" 2>/dev/null)

log "------------------------------------------"
log "shop.orders 行数对比： 生产=${PROD_COUNT}  恢复后=${TEST_COUNT}"

if [[ -n "$PROD_COUNT" && "$PROD_COUNT" == "$TEST_COUNT" ]]; then
    log "[SUCCESS] 恢复演练通过：数据行数一致，备份有效 ✔"
    log "STATUS=RESTORE_OK rows=${TEST_COUNT}"
    exit 0
else
    log "[FAILED] 行数不一致或无法读取，备份可能有问题 ✘"
    log "STATUS=RESTORE_FAILED prod=${PROD_COUNT} test=${TEST_COUNT}"
    exit 1
fi
