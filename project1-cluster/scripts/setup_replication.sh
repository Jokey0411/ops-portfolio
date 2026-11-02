#!/usr/bin/env bash
# =============================================================
#  在线搭建 MySQL 主从复制（GTID 模式）
#  前置：docker compose up -d 已执行，node1-db / node2-db 都 healthy
#  用法：bash setup_replication.sh
# =============================================================
set -uo pipefail

ROOT_PASS="Root@123456"
REPL_USER="repl"
REPL_PASS="Repl@123456"
MASTER="node1-db"
SLAVE="node2-db"

GRN='\033[32m'; RED='\033[31m'; NC='\033[0m'
log()  { echo -e "${GRN}[$(date '+%H:%M:%S')] ✔${NC} $*"; }
err()  { echo -e "${RED}[$(date '+%H:%M:%S')] ✘${NC} $*"; }

m() { docker exec -e MYSQL_PWD="$ROOT_PASS" "$MASTER" mysql -uroot -N -B -e "$1" 2>/dev/null; }
s() { docker exec -e MYSQL_PWD="$ROOT_PASS" "$SLAVE"  mysql -uroot -N -B -e "$1" 2>/dev/null; }

echo "=========================================="
echo " 搭建 MySQL 主从复制 (GTID)"
echo "=========================================="

# ---------- 0. 预检 ----------
log "[0/6] 预检"
for c in "$MASTER" "$SLAVE"; do
    st=$(docker inspect -f '{{.State.Status}}' "$c" 2>/dev/null)
    hl=$(docker inspect -f '{{.State.Health.Status}}' "$c" 2>/dev/null)
    [[ "$st" == "running" ]] || { err "$c 未运行"; exit 1; }
    log "  $c: $st / health=$hl"
done
# server-id 必须不同
SID_M=$(m "SELECT @@server_id"); SID_S=$(s "SELECT @@server_id")
log "  server-id: master=${SID_M} slave=${SID_S}"
[[ "$SID_M" == "$SID_S" ]] && { err "server-id 相同(${SID_M})，复制必然失败！检查 master.cnf/slave.cnf"; exit 1; }

# ---------- 1. 主库创建复制账号 ----------
log "[1/6] 主库创建复制账号 ${REPL_USER}"
m "CREATE USER IF NOT EXISTS '${REPL_USER}'@'%' IDENTIFIED WITH mysql_native_password BY '${REPL_PASS}';"
m "GRANT REPLICATION SLAVE ON *.* TO '${REPL_USER}'@'%';"
m "FLUSH PRIVILEGES;"
log "  账号已创建"

# ---------- 2. 确认主库 GTID 已开启 ----------
log "[2/6] 检查主库 GTID"
GTID=$(m "SELECT @@gtid_mode")
[[ "$GTID" == "ON" ]] || { err "主库 gtid_mode=${GTID}，必须为 ON"; exit 1; }
log "  gtid_mode=${GTID}"

# ---------- 3. 从主库 dump 业务库 ----------
log "[3/6] 从主库导出业务库（--single-transaction 不锁表）"
DUMP="/tmp/master_dump_$(date +%s).sql"
# ★ 两个关键点（都是踩过的坑）：
#  1) 只导业务库 shop，绝不能 --all-databases —— 会把主库的 mysql 系统库一起倒进去，
#     覆盖从库自己的 mysql.user / 权限表，严重时从库连 root 都登不上
#  2) 不要 --set-gtid-purged=OFF —— 必须让 dump 头部写入 SET @@GLOBAL.GTID_PURGED，
#     告诉从库"这些事务我已有"。关掉的话从库 gtid_executed 是空的，
#     AUTO_POSITION 会认为从库啥都没有，从第一笔事务开始重放，
#     撞上刚导入的库表 → Worker 报错 → Replica_SQL_Running: No
docker exec -e MYSQL_PWD="$ROOT_PASS" "$MASTER" mysqldump -uroot \
    --single-transaction --quick --routines --triggers --events \
    --databases shop > "$DUMP" 2>/dev/null
if [[ ! -s "$DUMP" ]]; then err "导出失败或文件为空"; exit 1; fi
grep -q "GTID_PURGED" "$DUMP" || { err "dump 里没有 GTID_PURGED，导入后从库会从头重放"; exit 1; }
log "  导出完成：$(du -h "$DUMP" | cut -f1)（含 GTID_PURGED）"

# ---------- 4. 重置从库 GTID 状态并导入 ----------
log "[4/6] 重置从库并导入"
# GTID_PURGED 只能写入 gtid_executed 为空的实例，所以必须先清干净再导入。
# ★ 顺序不能反：DROP 库会产生一个新 GTID，所以要先 DROP、后 RESET MASTER，
#   否则 RESET 完再 DROP，gtid_executed 又不空了，导入时 GTID_PURGED 直接报错。
s "STOP REPLICA;"      2>/dev/null
s "RESET REPLICA ALL;" 2>/dev/null
s "DROP DATABASE IF EXISTS shop;" 2>/dev/null
s "RESET MASTER;"      2>/dev/null
docker exec -i -e MYSQL_PWD="$ROOT_PASS" "$SLAVE" mysql -uroot < "$DUMP" 2>/dev/null
log "  导入完成，从库表数量：$(s "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema NOT IN ('mysql','sys','performance_schema','information_schema')")"

# ---------- 5. 配置并启动复制 ----------
log "[5/6] 配置复制链路"
s "STOP REPLICA;" 2>/dev/null
s "RESET REPLICA ALL;" 2>/dev/null
s "CHANGE REPLICATION SOURCE TO SOURCE_HOST='${MASTER}', SOURCE_PORT=3306, \
   SOURCE_USER='${REPL_USER}', SOURCE_PASSWORD='${REPL_PASS}', \
   SOURCE_AUTO_POSITION=1, SOURCE_CONNECT_RETRY=10;" 2>/dev/null
s "START REPLICA;" 2>/dev/null
sleep 3

# ---------- 6. 验证 ----------
log "[6/6] 验证复制状态"
for i in $(seq 1 15); do
    IO=$(docker exec -e MYSQL_PWD="$ROOT_PASS" "$SLAVE" mysql -uroot -e "SHOW REPLICA STATUS\G" 2>/dev/null | grep -m1 'Replica_IO_Running:' | awk '{print $2}')
    SQL=$(docker exec -e MYSQL_PWD="$ROOT_PASS" "$SLAVE" mysql -uroot -e "SHOW REPLICA STATUS\G" 2>/dev/null | grep -m1 'Replica_SQL_Running:' | awk '{print $2}')
    [[ "$IO" == "Yes" && "$SQL" == "Yes" ]] && break
    sleep 2
done

docker exec -e MYSQL_PWD="$ROOT_PASS" "$SLAVE" mysql -uroot -e "SHOW REPLICA STATUS\G" 2>/dev/null \
    | grep -E 'Replica_IO_Running|Replica_SQL_Running|Seconds_Behind_Master|Last_IO_Error|Last_SQL_Error|Auto_Position'

if [[ "$IO" == "Yes" && "$SQL" == "Yes" ]]; then
    log "主从复制搭建成功！"
    echo ""
    echo "验证方法（强烈建议跑一遍，面试要讲）："
    echo "  1) 主库写入："
    echo "     docker exec -e MYSQL_PWD=${ROOT_PASS} ${MASTER} mysql -uroot -e \\"
    echo "       \"INSERT INTO shop.orders (user_id,product,amount,status) VALUES (99,'repl-test',1.11,'paid');\""
    echo "  2) 从库查询（应立刻能看到）："
    echo "     docker exec -e MYSQL_PWD=${ROOT_PASS} ${SLAVE} mysql -uroot -e \\"
    echo "       \"SELECT id,product FROM shop.orders WHERE user_id=99;\""
    echo "  3) 看延迟："
    echo "     docker exec -e MYSQL_PWD=${ROOT_PASS} ${SLAVE} mysql -uroot -e 'SHOW REPLICA STATUS\G' | grep Seconds_Behind"
else
    err "复制未启动成功，排查方向："
    echo "  1) 从库错误日志：docker logs ${SLAVE} 2>&1 | tail -50"
    echo "  2) 网络连通：docker exec ${SLAVE} sh -c 'nc -zv ${MASTER} 3306'  (或用 python 测)"
    echo "  3) 账号权限：主库执行 SHOW GRANTS FOR '${REPL_USER}'@'%'"
    echo "  4) server-id 冲突：SELECT @@server_id 两边必须不同"
    exit 1
fi
