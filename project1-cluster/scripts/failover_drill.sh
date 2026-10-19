#!/usr/bin/env bash
# =============================================================
#  故障演练：验证 LB 能否自动摘除故障节点
#  这是简历"集群"二字唯一的硬证据 —— 光说高可用没用，得敢停服务看结果
#  用法：bash failover_drill.sh
# =============================================================
set -uo pipefail

GRN='\033[32m'; RED='\033[31m'; YEL='\033[33m'; NC='\033[0m'
log()  { echo -e "${GRN}[$(date '+%H:%M:%S')] ✔${NC} $*"; }
warn() { echo -e "${YEL}[$(date '+%H:%M:%S')] ⚠${NC} $*"; }
err()  { echo -e "${RED}[$(date '+%H:%M:%S')] ✘${NC} $*"; }

TARGET="${1:-node1-web}"
N="${2:-20}"

echo "=========================================="
echo " 故障演练：停掉 ${TARGET}，观察流量切换"
echo "=========================================="

echo ""
log "演练前：连续 ${N} 次请求，观察后端分布"
for i in $(seq 1 "$N"); do
    node=$(curl -s -o /dev/null -w '%{header_json}' -m 3 http://127.0.0.1/whoami 2>/dev/null | grep -o '"x-served-by":\["[^"]*"' | sed 's/.*:"//')
    printf '%s ' "${node:-?}"
done
echo ""
echo ""

warn ">>> 现在停止 ${TARGET} ..."
docker stop "$TARGET" >/dev/null 2>&1
log "${TARGET} 已停止"
echo ""

sleep 2
log "演练中：连续 ${N} 次请求（预期：全部打到存活节点，无 502）"
FAIL=0
for i in $(seq 1 "$N"); do
    out=$(curl -s -o /dev/null -w '%{http_code} %{header_json}' -m 3 http://127.0.0.1/whoami 2>/dev/null)
    code=$(echo "$out" | awk '{print $1}')
    node=$(echo "$out" | grep -o '"x-served-by":\["[^"]*"' | sed 's/.*:"//')
    printf '%s:%s ' "${code}" "${node:-?}"
    [[ "$code" != "200" ]] && FAIL=$((FAIL+1))
    sleep 0.2
done
echo ""
echo ""

if [[ $FAIL -eq 0 ]]; then
    log "结果：${N} 次请求全部 200，LB 成功摘除故障节点 ✔"
else
    err "结果：${FAIL}/${N} 次请求失败"
    echo "  排查：docker logs lb 2>&1 | tail -30"
fi

echo ""
warn ">>> 恢复 ${TARGET} ..."
docker start "$TARGET" >/dev/null 2>&1
for i in $(seq 1 15); do
    st=$(docker inspect -f '{{.State.Status}}' "$TARGET" 2>/dev/null)
    [[ "$st" == "running" ]] && break
    sleep 1
done
sleep 3
log "恢复后：连续 10 次请求"
for i in $(seq 1 10); do
    node=$(curl -s -o /dev/null -w '%{header_json}' -m 3 http://127.0.0.1/whoami 2>/dev/null | grep -o '"x-served-by":\["[^"]*"' | sed 's/.*:"//')
    printf '%s ' "${node:-?}"
done
echo ""
echo ""
log "演练结束。把上面的输出截图/记录下来，写进故障复盘文档。"
