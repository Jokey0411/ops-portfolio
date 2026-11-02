#!/usr/bin/env bash
# =============================================================
#  备份恢复演练 —— 备份不验证等于没备份
#  ★ 这是面试官最爱的追问："你怎么确认备份是有效的？"
#  做法：起一个临时 MySQL 容器，把最新全量备份灌进去，
#        校验「表数量 + 关键表行数 + 索引数量」三项与生产一致
#  用法：bash scripts/restore_test.sh
# =============================================================
set -uo pipefail

BACKUP_DIR="${BACKUP_DIR:-/opt/ops/backup/mysql}"
RESULT_LOG="${RESULT_LOG:-/opt/ops/logs/scripts/restore-test.log}"

# 生产库（被校验对象）
PROD_CONTAINER="${PROD_CONTAINER:-lnmp-mysql}"
PROD_PASS="${PROD_PASS:-Root@123456}"

# 临时恢复库
TEST_CONTAINER="restore-test-$$"
TEST_PASS="Restore@123"
# ★ 限制 512m：2G 机器上生产 MySQL 已占 300~500m，
#   不设上限时 Docker 会把宿主机吃满，直接触发 OOM Kill 把生产库一起干掉。
TEST_MEM="${TEST_MEM:-512m}"

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
log "备份年龄: $(( ($(date +%s) - $(stat -c %Y "$LATEST")) / 60 )) 分钟前"

# ---------------- 2. 起临时容器 ----------------
# 只给 64M buffer pool：恢复是顺序写入，不需要大缓存，省内存比快更重要
log "启动临时 MySQL 容器 ${TEST_CONTAINER} (mem=${TEST_MEM}) ..."
docker run -d --name "$TEST_CONTAINER" \
    -e MYSQL_ROOT_PASSWORD="$TEST_PASS" \
    --memory "$TEST_MEM" \
    --tmpfs /tmp \
    mysql:8.0 \
    --innodb-buffer-pool-size=64M >/dev/null 2>&1

cleanup() {
    log "清理临时容器"
    docker rm -f "$TEST_CONTAINER" >/dev/null 2>&1
}
trap cleanup EXIT

# 等待就绪（MySQL 首次启动要 40~90 秒）
log "等待 MySQL 就绪..."
READY=0
for i in $(seq 1 60); do
    if docker exec -e MYSQL_PWD="$TEST_PASS" "$TEST_CONTAINER" \
            mysqladmin ping -uroot --silent &>/dev/null; then
        log "  MySQL 就绪（等待 $((i * 2)) 秒）"
        READY=1
        break
    fi
    sleep 2
done
if [[ $READY -eq 0 ]]; then
    log "[FAILED] 临时容器 120 秒内未就绪，看日志：docker logs $TEST_CONTAINER"
    exit 1
fi

# ---------------- 3. 恢复 ----------------
# ★ 这里刻意不用 `| head -10`：head 读够 10 行就退出，会提前关掉管道，
#   zcat 收到 SIGPIPE(141) 立刻死掉 → **恢复只导入了前几 MB，却"看起来成功"**。
#   用 PIPESTATUS 分别检查两端退出码，把这个问题变成一条硬断言。
RESTORE_OUT=$(mktemp)
log "开始恢复..."
START=$(date +%s)
zcat "$LATEST" | docker exec -i -e MYSQL_PWD="$TEST_PASS" "$TEST_CONTAINER" \
        mysql -uroot --force > "$RESTORE_OUT" 2>&1
RC_ZCAT=${PIPESTATUS[0]}
RC_MYSQL=${PIPESTATUS[1]}
END=$(date +%s)
log "恢复完成，耗时 $((END - START))s (zcat=${RC_ZCAT}, mysql=${RC_MYSQL})"

# 导入报错（--force 下会继续跑完，但错误一定要看）
# 注意不能写成 `grep -c ... || echo 0`：grep -c 无匹配时已经输出 0、退出码 1，
# 再加 echo 0 就变成两行 "0"，后面 [[ -gt ]] 会直接语法报错。
ERR_CNT=$(grep -c '^ERROR' "$RESTORE_OUT" 2>/dev/null)
ERR_CNT=${ERR_CNT:-0}
if [[ "$ERR_CNT" -gt 0 ]]; then
    log "恢复过程有 ${ERR_CNT} 条 ERROR（前 5 条）："
    grep '^ERROR' "$RESTORE_OUT" | head -5 | while read -r l; do log "  $l"; done
fi
rm -f "$RESTORE_OUT"

# zcat=141 说明管道被提前关闭，导出根本没读完 → 必须判失败
if [[ "$RC_ZCAT" -ne 0 ]]; then
    log "[FAILED] 管道异常退出（zcat=${RC_ZCAT}，141=SIGPIPE），备份未完整导入 ✘"
    log "STATUS=RESTORE_FAILED reason=pipe_closed zcat=${RC_ZCAT}"
    exit 1
fi

# ---------------- 4. 三项校验 ----------------
q_prod() {
    docker exec -e MYSQL_PWD="$PROD_PASS" "$PROD_CONTAINER" \
        mysql -uroot -N -B -e "$1" 2>/dev/null
}
q_test() {
    docker exec -e MYSQL_PWD="$TEST_PASS" "$TEST_CONTAINER" \
        mysql -uroot -N -B -e "$1" 2>/dev/null
}

# 4.1 表数量
SQL_TBL="SELECT COUNT(*) FROM information_schema.tables
         WHERE table_schema='shop';"
# 4.2 关键表行数（COUNT(*) 是真数，information_schema.table_rows 是估算值，不能用来校验）
SQL_ROWS="SELECT COUNT(*) FROM shop.orders;"
# 4.3 索引数量（只比行数会漏掉「数据在但索引丢了」的情况，索引丢了性能直接回到优化前）
SQL_IDX="SELECT COUNT(DISTINCT index_name) FROM information_schema.statistics
         WHERE table_schema='shop' AND table_name='orders';"

P_TBL=$(q_prod "$SQL_TBL"); T_TBL=$(q_test "$SQL_TBL")
P_ROWS=$(q_prod "$SQL_ROWS"); T_ROWS=$(q_test "$SQL_ROWS")
P_IDX=$(q_prod "$SQL_IDX"); T_IDX=$(q_test "$SQL_IDX")

log "------------------------------------------"
log "校验项            生产        恢复后      结果"
chk() {
    [[ -n "$1" && "$1" == "$2" ]] && echo "一致 ✔" || echo "不一致 ✘"
}
log "shop 表数量       ${P_TBL:-NULL}        ${T_TBL:-NULL}        $(chk "$P_TBL" "$T_TBL")"
log "orders 行数       ${P_ROWS:-NULL}     ${T_ROWS:-NULL}     $(chk "$P_ROWS" "$T_ROWS")"
log "orders 索引数     ${P_IDX:-NULL}         ${T_IDX:-NULL}         $(chk "$P_IDX" "$T_IDX")"

# 4.5 恢复后的索引明细，肉眼可核
log "恢复后 orders 索引："
q_test "SELECT DISTINCT index_name, GROUP_CONCAT(column_name ORDER BY seq_in_index)
        FROM information_schema.statistics
        WHERE table_schema='shop' AND table_name='orders'
        GROUP BY index_name;" | while read -r l; do log "  $l"; done

# ---------------- 5. 判定 ----------------
if [[ -n "$P_ROWS" && "$P_ROWS" == "$T_ROWS" && "$P_TBL" == "$T_TBL" && "$P_IDX" == "$T_IDX" ]]; then
    log "[SUCCESS] 恢复演练通过：表数 / 行数 / 索引数三项一致，备份有效 ✔"
    log "STATUS=RESTORE_OK tables=${T_TBL} rows=${T_ROWS} idx=${T_IDX} cost=$((END - START))s"
    exit 0
else
    log "[FAILED] 校验不通过，备份可能有问题 ✘"
    log "STATUS=RESTORE_FAILED tbl=${P_TBL}/${T_TBL} rows=${P_ROWS}/${T_ROWS} idx=${P_IDX}/${T_IDX}"
    exit 1
fi
