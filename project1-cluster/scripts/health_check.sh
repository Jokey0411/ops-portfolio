#!/usr/bin/env bash
# =============================================================
#  集群健康检查：LB / 双节点 / 主从复制 / 磁盘 / 内存
#  发现异常立即告警（简历："异常告警"）
#  crontab: */5 * * * * /opt/ops/project1-cluster/scripts/health_check.sh >> /opt/ops/logs/scripts/health-cron.log 2>&1
# =============================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_DIR="${LOG_DIR:-/opt/ops/logs/scripts}"
LOG="${LOG_DIR}/health.log"
MYSQL_PASS="Root@123456"
DISK_THRESHOLD=85
MEM_THRESHOLD=90
LAG_THRESHOLD=30        # 主从延迟超过 30 秒告警

mkdir -p "$LOG_DIR"
log() { echo "[$(date '+%F %T')] $*" | tee -a "$LOG"; }

ALARMS=()

# ---------------- 1. 容器存活 ----------------
log "---- 容器存活检查 ----"
for c in lb node1-web node1-app node1-db node2-web node2-app node2-db; do
    st=$(docker inspect -f '{{.State.Status}}' "$c" 2>/dev/null)
    if [[ "$st" == "running" ]]; then
        log "  ✔ $c running"
    else
        log "  ✘ $c 状态异常: ${st:-不存在}"
        ALARMS+=("容器 $c 状态=${st:-缺失}")
    fi
done

# ---------------- 2. HTTP 可达性 ----------------
log "---- HTTP 检查 ----"
LB_CODE=$(curl -s -o /dev/null -w '%{http_code}' -m 5 http://127.0.0.1/healthz 2>/dev/null)
if [[ "$LB_CODE" == "200" ]]; then
    log "  ✔ LB /healthz 200"
else
    log "  ✘ LB 返回 ${LB_CODE}"
    ALARMS+=("LB 健康检查失败，HTTP=${LB_CODE}")
fi

for n in node1-web node2-web; do
    ip=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$n" 2>/dev/null | head -1)
    code=$(curl -s -o /dev/null -w '%{http_code}' -m 5 "http://${ip}/healthz" 2>/dev/null)
    if [[ "$code" == "200" ]]; then
        log "  ✔ $n(${ip}) /healthz 200"
    else
        log "  ✘ $n(${ip}) HTTP=${code}"
        ALARMS+=("节点 $n 健康检查失败 HTTP=${code}")
    fi
done

# ---------------- 3. MySQL 主从状态（★核心）----------------
log "---- MySQL 主从复制检查 ----"
SLAVE_OUT=$(docker exec -e MYSQL_PWD="${MYSQL_PASS}" node2-db \
    mysql -uroot -e "SHOW REPLICA STATUS\G" 2>/dev/null)

if [[ -z "$SLAVE_OUT" ]]; then
    log "  ✘ 无法获取从库复制状态"
    ALARMS+=("从库 node2-db 复制状态获取失败")
else
    IO_RUN=$(echo "$SLAVE_OUT"  | grep -m1 'Replica_IO_Running:'  | awk '{print $2}')
    SQL_RUN=$(echo "$SLAVE_OUT" | grep -m1 'Replica_SQL_Running:' | awk '{print $2}')
    LAG=$(echo "$SLAVE_OUT"     | grep -m1 'Seconds_Behind_Master:' | awk '{print $2}')
    LAST_ERR=$(echo "$SLAVE_OUT" | grep -m1 'Last_Error:' | sed 's/^ *Last_Error: //')
    log "  IO线程=${IO_RUN}  SQL线程=${SQL_RUN}  延迟=${LAG}s"

    [[ "$IO_RUN" != "Yes" ]] && ALARMS+=("主从复制 IO 线程停止，Last_Error: ${LAST_ERR:0:200}")
    [[ "$SQL_RUN" != "Yes" ]] && ALARMS+=("主从复制 SQL 线程停止，Last_Error: ${LAST_ERR:0:200}")
    if [[ "$LAG" =~ ^[0-9]+$ ]] && [[ "$LAG" -gt "$LAG_THRESHOLD" ]]; then
        ALARMS+=("主从延迟 ${LAG}s，超过阈值 ${LAG_THRESHOLD}s")
    fi
fi

# 主库可写性检查
if docker exec -e MYSQL_PWD="${MYSQL_PASS}" node1-db mysql -uroot -e "SELECT 1" &>/dev/null; then
    log "  ✔ 主库 node1-db 可连接"
else
    ALARMS+=("主库 node1-db 无法连接")
    log "  ✘ 主库连接失败"
fi

# ---------------- 4. 资源检查 ----------------
log "---- 资源检查 ----"
DISK_USE=$(df / | awk 'NR==2{print $5}' | tr -d '%')
MEM_USE=$(free | awk '/^Mem:/{printf "%d", $3/$2*100}')
log "  磁盘 ${DISK_USE}%  内存 ${MEM_USE}%"
[[ "$DISK_USE" -ge "$DISK_THRESHOLD" ]] && ALARMS+=("根分区磁盘使用率 ${DISK_USE}%，超过 ${DISK_THRESHOLD}%")
[[ "$MEM_USE"  -ge "$MEM_THRESHOLD"  ]] && ALARMS+=("内存使用率 ${MEM_USE}%，超过 ${MEM_THRESHOLD}%")

# 单容器内存占用 Top3（2G 机器要盯紧）
log "  容器内存占用 Top3:"
docker stats --no-stream --format '{{.Name}} {{.MemUsage}}' 2>/dev/null | head -3 | while read -r line; do
    log "    $line"
done

# ---------------- 汇总告警 ----------------
if [[ ${#ALARMS[@]} -eq 0 ]]; then
    log "✔ 全部检查通过"
    exit 0
else
    BODY=""
    for a in "${ALARMS[@]}"; do BODY="${BODY}\n- ${a}"; done
    log "✘ 发现 ${#ALARMS[@]} 项异常，触发告警"
    bash "${SCRIPT_DIR}/notify.sh" "集群健康检查告警" "$(printf "%b" "$BODY")" critical
    exit 1
fi
