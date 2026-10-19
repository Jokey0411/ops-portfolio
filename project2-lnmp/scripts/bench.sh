#!/usr/bin/env bash
# =============================================================
#  SQL 优化基准测试：自动采集优化前后的 EXPLAIN 与耗时
#  用法：
#    bash scripts/bench.sh before    # 建索引之前跑
#    bash scripts/bench.sh after     # 建索引之后跑
#  输出：docs/benchmark_before.txt / benchmark_after.txt
#  ★ 用真实数字填进 docs/SQL优化记录.md，不要凭感觉写"提升了 X%"
# =============================================================
set -uo pipefail

STAGE="${1:-before}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
OUT="${PROJECT_DIR}/docs/benchmark_${STAGE}.txt"
CONTAINER="${CONTAINER:-lnmp-mysql}"
MYSQL_USER="root"
MYSQL_PASS="Root@123456"
RUNS="${RUNS:-3}"          # 每个查询跑几次取最小值

mkdir -p "$(dirname "$OUT")"
mq() { docker exec -e MYSQL_PWD="${MYSQL_PASS}" "$CONTAINER" mysql -u"${MYSQL_USER}" -N -B -e "$1" 2>&1; }
mqt() { docker exec -e MYSQL_PWD="${MYSQL_PASS}" "$CONTAINER" mysql -u"${MYSQL_USER}" -e "$1" 2>&1; }

declare -a NAMES=(
  "Q1 用户订单分页(WHERE等值+ORDER BY+LIMIT)"
  "Q2 分组统计(GROUP BY)"
  "Q3 范围条件+排序"
  "Q4 JOIN 查询"
)
declare -a SQLS=(
  "SELECT id,user_id,amount,status,created_at FROM shop.orders WHERE user_id=100 AND status='paid' ORDER BY created_at DESC LIMIT 20;"
  "SELECT user_id, SUM(amount) FROM shop.orders WHERE status='done' GROUP BY user_id;"
  "SELECT id,city,amount,created_at FROM shop.orders WHERE city='Nanjing' AND created_at >= '2025-06-01' ORDER BY amount DESC LIMIT 20;"
  "SELECT o.id,u.username,o.amount FROM shop.orders o JOIN shop.users u ON o.user_id=u.id WHERE o.status='paid' AND u.city='Nanjing' LIMIT 20;"
)

{
echo "=============================================================="
echo " SQL 基准测试 —— 阶段: ${STAGE}"
echo " 时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo " 容器: ${CONTAINER}  每查询执行 ${RUNS} 次取最小值"
echo "=============================================================="
echo ""
echo "--- 环境信息 ---"
mq "SELECT VERSION();" | sed 's/^/MySQL 版本: /'
mq "SELECT @@innodb_buffer_pool_size/1024/1024;" | sed 's/^/buffer_pool(MB): /'
mq "SELECT table_name, table_rows FROM information_schema.tables WHERE table_schema='shop';"
echo ""
echo "--- 当前索引 ---"
mqt "SELECT table_name, index_name, GROUP_CONCAT(column_name ORDER BY seq_in_index) AS cols FROM information_schema.statistics WHERE table_schema='shop' GROUP BY table_name, index_name;"
echo ""
} | tee "$OUT"

for i in "${!SQLS[@]}"; do
    NAME="${NAMES[$i]}"
    SQL="${SQLS[$i]}"
    {
    echo "=============================================================="
    echo " ${NAME}"
    echo "--------------------------------------------------------------"
    echo "SQL: ${SQL}"
    echo ""
    echo "--- EXPLAIN ---"
    mqt "EXPLAIN ${SQL}"
    echo ""
    echo "--- EXPLAIN ANALYZE（真实执行耗时）---"
    mqt "EXPLAIN ANALYZE ${SQL}" 2>&1 | grep -oE 'actual time=[0-9.]+' | head -5
    echo ""
    echo "--- 执行耗时（${RUNS} 次，单位 ms）---"
    BEST=999999
    for r in $(seq 1 "$RUNS"); do
        S=$(date +%s%3N)
        mq "${SQL}" > /dev/null 2>&1
        E=$(date +%s%3N)
        COST=$((E - S))
        echo "  第 ${r} 次: ${COST} ms"
        [[ $COST -lt $BEST ]] && BEST=$COST
    done
    echo "  最快: ${BEST} ms"
    echo ""
    } | tee -a "$OUT"
done

{
echo "=============================================================="
echo " 慢查询日志统计（优化后应该明显减少）"
echo "=============================================================="
docker exec "$CONTAINER" sh -c 'test -f /var/log/mysql/slow.log && wc -l /var/log/mysql/slow.log || echo "慢日志尚未生成"'
echo ""
echo "--- mysqldumpslow 汇总（Top 5）---"
docker exec "$CONTAINER" sh -c 'mysqldumpslow -s t -t 5 /var/log/mysql/slow.log 2>/dev/null || echo "无慢查询或命令不可用"'
echo ""
echo "完成。结果已保存到 ${OUT}"
echo "把数据填进 docs/SQL优化记录.md 的对比表"
} | tee -a "$OUT"
