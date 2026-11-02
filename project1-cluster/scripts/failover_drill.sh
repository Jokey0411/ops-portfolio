#!/usr/bin/env bash
# =============================================================
#  故障演练：验证 LB 能否自动摘除故障节点
#  这是简历"集群"二字唯一的硬证据 —— 光说高可用没用，得敢停服务看结果
#
#  用法（在任意目录都能跑）：
#      bash scripts/failover_drill.sh                  # 默认 node1-web，20 次
#      bash scripts/failover_drill.sh node1-web 20
#      bash scripts/failover_drill.sh node2-web 30
# =============================================================
set -uo pipefail

# ---- 自定位：无论从哪个目录调用，都切到 project1-cluster/ ----
# 为什么需要：脚本里所有 docker / curl 调用都假设「已经在项目目录」，
# 站错目录报的错会非常迷惑（见 docs/08 第 12、17 坑）
cd "$(dirname "$(readlink -f "$0")")/.." || {
    echo "✘ 无法定位项目目录"; exit 1;
}

GRN='\033[32m'; RED='\033[31m'; YEL='\033[33m'; NC='\033[0m'
log()  { echo -e "${GRN}[$(date '+%H:%M:%S')] ✔${NC} $*"; }
warn() { echo -e "${YEL}[$(date '+%H:%M:%S')] ⚠${NC} $*"; }
err()  { echo -e "${RED}[$(date '+%H:%M:%S')] ✘${NC} $*"; }

TARGET="${1:-node1-web}"
N="${2:-20}"
URL="${DRILL_URL:-http://127.0.0.1/whoami}"
# ★ 客户端超时必须 > nginx 的 proxy_connect_timeout，否则你测到的是「自己放弃了」，
#   而不是「nginx 放弃了」。旧版用 -m 3，正好和 proxy_connect_timeout 3s 撞在一起，
#   于是「nginx 正在重试」被记成了「000 失败」——把慢故障伪装成硬故障。
TIMEOUT="${DRILL_TIMEOUT:-8}"

HDR=$(mktemp) || exit 1
cleanup() {
    rm -f "$HDR"
    # ★ 兜底恢复：Ctrl-C / 脚本中途报错时，别把节点留在停止状态
    if [[ "${STOPPED:-0}" == "1" ]]; then
        echo ""
        warn "检测到异常退出，正在恢复 ${TARGET} ..."
        docker start "$TARGET" >/dev/null 2>&1 && log "${TARGET} 已恢复"
    fi
}
trap cleanup EXIT
# ★ 不用 trap ... INT TERM 直接调 cleanup：那样中断后脚本还会继续往下跑。
#   正确做法是中断 → exit → 由 EXIT trap 统一收尾
trap 'exit 130' INT TERM

# ---- 从响应头里取某个字段的值（字段名大小写不敏感）----
# ★ 不用 curl 的 %{header_json}：那是 curl 7.83+ 才有的，CentOS/OpenCloudOS
#   自带 curl 7.61~7.76，用了它不报错、只静默返回空值，节点列全是 "?"
# ★ 不用 awk -F':' 切分：X-Upstream-Node 的值本身带冒号（172.20.0.12:80），
#   按冒号切会把端口切掉，所以只切第一个冒号
hdr_val() {
    tr -d '\r' < "$HDR" 2>/dev/null | awk -v k="$1" '
        tolower($0) ~ "^" k ":" {
            sub(/^[^:]*:[[:space:]]*/, ""); sub(/[[:space:]]+$/, ""); print; exit
        }'
}

# ---- 单次探测：返回 "HTTP码 节点名 耗时毫秒" ----
# ★ 关键是第三个字段。只看 200/000 分不清「失败」和「慢」：
#   3 秒才失败和 3 毫秒就失败，是完全不同的两个故障。
probe() {
    local code node up t
    code=$(curl -s -m "$TIMEOUT" -D "$HDR" -o /dev/null \
           -w '%{http_code} %{time_total}' "$URL" 2>/dev/null)
    t=$(echo "$code" | awk '{printf "%d", ($2 ? $2*1000 : 0)}')
    code=$(echo "$code" | awk '{print ($1 == "" ? "000" : $1)}')
    node=$(hdr_val x-served-by)
    if [[ -z "$node" ]]; then
        # 兜底：节点挂了时 X-Served-By 可能拿不到，但 lb 自己写的 X-Upstream-Node 还在
        up=$(hdr_val x-upstream-node)
        node="${up:+upstream:$up}"
    fi
    printf '%s %s %s' "$code" "${node:-?}" "${t:-0}"
}

echo "=========================================="
echo " 故障演练：停掉 ${TARGET}，观察流量切换"
echo " 工作目录：$(pwd)"
echo "=========================================="
echo ""

# ---- 前置检查：三个条件不满足，演练结果没有意义 ----
PRE_OK=1
if ! docker inspect -f '{{.State.Running}}' lb 2>/dev/null | grep -q true; then
    err "lb 容器没在运行 → docker compose up -d"; PRE_OK=0
fi
if ! docker inspect -f '{{.State.Running}}' "$TARGET" 2>/dev/null | grep -q true; then
    err "目标容器 ${TARGET} 没在运行 → 先 docker ps 看真实名字"; PRE_OK=0
fi
read -r _ FIRST_NODE _ <<< "$(probe)"
if [[ "$FIRST_NODE" == "?" ]]; then
    err "${URL} 拿不到 X-Served-By 响应头 → 先 curl -i ${URL} 看返回"
    PRE_OK=0
fi
[[ $PRE_OK -eq 0 ]] && { echo ""; err "前置检查未通过，演练中止"; exit 1; }
log "前置检查通过（lb 在跑、${TARGET} 在跑、响应头可读）"
echo ""

T0=$(date +%s)
log "演练前：连续 ${N} 次请求，观察后端分布"
MAXT=0
for i in $(seq 1 "$N"); do
    read -r code node t <<< "$(probe)"
    printf '%s ' "${node:-?}"
    [[ "$t" -gt "$MAXT" ]] && MAXT=$t
done
echo "  (最慢 ${MAXT}ms)"
echo ""

warn ">>> 现在停止 ${TARGET} ..."
if docker stop "$TARGET" >/dev/null 2>&1; then
    STOPPED=1
    log "${TARGET} 已停止"
else
    err "停止 ${TARGET} 失败"; exit 1
fi
echo ""

sleep 2
log "演练中：连续 ${N} 次请求（预期：全部 200，且都打到存活节点）"
echo "    格式：状态码:节点(耗时ms)，超过 1000ms 会标黄"
FAIL=0; SLOW=0; MAXT=0; SURVIVOR=""; FAIL_DETAIL=""; LAST_SLOW=0
for i in $(seq 1 "$N"); do
    read -r code node t <<< "$(probe)"
    if [[ "$t" -gt 1000 ]]; then
        printf "${YEL}%s:%s(%sms)${NC} " "$code" "$node" "$t"
        SLOW=$((SLOW+1)); LAST_SLOW=$i
    else
        printf '%s:%s(%sms) ' "$code" "$node" "$t"
    fi
    [[ "$t" -gt "$MAXT" ]] && MAXT=$t
    if [[ "$code" != "200" ]]; then
        FAIL=$((FAIL+1))
        FAIL_DETAIL+=" #${i}=${code}(${t}ms)"
    fi
    [[ "$node" != "?" && -n "$node" ]] && SURVIVOR=$node
    sleep 0.2
done
ELAPSED=$(( $(date +%s) - T0 ))
echo ""
echo ""

log "统计：${N} 次 / 失败 ${FAIL} / 超 1s ${SLOW} / 最慢 ${MAXT}ms / 全程 ${ELAPSED}s"
[[ -n "$FAIL_DETAIL" ]] && echo "    失败明细：${FAIL_DETAIL}"
if [[ $SLOW -gt 0 ]]; then
    echo "    最后一次慢请求在第 ${LAST_SLOW} 次 —— 之后就全快了，说明摘除在第 ${LAST_SLOW} 次请求后完成"
    echo "    理论上限 = max_fails × proxy_connect_timeout × 2(轮询要隔一次才轮到它)"
fi

if [[ $FAIL -eq 0 ]]; then
    log "结论：${N} 次请求全部 200，LB 成功摘除故障节点 ✔"
    [[ $SLOW -gt 0 ]] && warn "但有 ${SLOW} 次超过 1 秒 —— 这是「能用但慢」，不是「无感切换」"
    log "当前承接流量的节点：${SURVIVOR:-（未识别）}"
else
    err "结论：${FAIL}/${N} 次请求失败，LB 摘除不彻底"
    echo "  排查顺序（别跳步）："
    echo "    ① 看失败耗时，先分清是「谁放弃了」："
    echo "         ≈${TIMEOUT}000ms → curl 自己超时（把 DRILL_TIMEOUT 调到 15 再跑一次）"
    echo "         ≈1000ms        → nginx 在等 proxy_connect_timeout（属正常，只是慢）"
    echo "         <50ms          → 是 502，连接被立刻拒绝"
    echo "    ② 看 nginx 记了多少 499（499 = 客户端先断，nginx 还没应答）："
    echo "         docker exec lb tail -60 /var/log/nginx/lb_access.log"
    echo "       ★ 499 多 = 你的超时设小了，测的是自己不是 LB"
    echo "    ③ 看错误日志（注意：日志挂在宿主机，docker logs 里是空的）："
    echo "         tail -30 logs/nginx-lb/lb_error.log | grep -i upstream"
    echo "    ④ 常见根因：max_fails/fail_timeout 没配，或 proxy_next_upstream 被改成 off"
fi

echo ""
warn ">>> 恢复 ${TARGET} ..."
docker start "$TARGET" >/dev/null 2>&1
STOPPED=0
for i in $(seq 1 15); do
    st=$(docker inspect -f '{{.State.Status}}' "$TARGET" 2>/dev/null)
    [[ "$st" == "running" ]] && break
    sleep 1
done
sleep 3
log "恢复后：连续 10 次请求（预期：两个节点重新交替出现）"
for i in $(seq 1 10); do
    read -r code node t <<< "$(probe)"
    printf '%s(%sms) ' "${node:-?}" "$t"
done
echo ""
echo ""
log "演练结束。把上面的输出截图/记录下来，写进故障复盘文档。"
