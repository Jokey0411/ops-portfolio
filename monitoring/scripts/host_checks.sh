#!/bin/bash
# ============================================================
# 宿主机采集脚本 —— 把「容器里的业务指标」推给 Zabbix
#
# ── 为什么不在 agent2 容器里用 UserParameter？ ──
#   读主从状态要 `docker exec` 进 MySQL 容器，而 agent2 是 alpine(musl)，
#   宿主机的 /usr/bin/docker 是 glibc 动态链接的，挂进容器后执行会得到：
#       exec /usr/bin/docker: no such file or directory
#   注意这个报错不是「文件不存在」，是 ELF 装载器 /lib64/ld-linux-x86-64.so.2
#   在 alpine 里根本没有，内核 execve() 直接 ENOENT。缺的是依赖链，不是文件。
#
# ── 为什么用 push 而不是 pull？ ──
#   采集需要「宿主机的上下文」（docker CLI、能读宿主机路径），
#   这份能力 agent2 在容器里拿不到。push 模式把职责分开：
#   脚本负责执行，server 负责存储和判定。
#
#   另一个更重要的理由：**失败要可见**。
#   如果改成「脚本写文件 → agent 用 vfs.file.contents 读」，
#   cron 挂了以后 agent 会一直返回文件里的旧值 —— 监控显示一切正常，
#   实际早就没人采集了。push 模式下 cron 一挂就没数据，item 变 stale，
#   触发器立刻能抓到。**不要让数据骗你**，这是本项目反复出现的主题。
#
# ── 用法 ──
#   bash host_checks.sh              # 正常采集并推送
#   bash host_checks.sh --dry-run    # 只打印不推送，用来验证取值对不对
# ============================================================

set -uo pipefail

# ★ cron 的 PATH 极短（通常只有 /usr/bin:/bin），不显式设置会找不到 docker。
#   这就是 docs/08 第 13 坑，这里必须写死。
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export TZ=Asia/Shanghai

# ---------------- 配置（都可用环境变量覆盖） ----------------
ZBX_SERVER="${ZBX_SERVER:-127.0.0.1}"
ZBX_PORT="${ZBX_PORT:-10051}"
# ★ 必须和 Zabbix 界面里 Host name 完全一致，trapper item 靠这个名字匹配
ZBX_HOSTNAME="${ZBX_HOSTNAME:-$(hostname)}"
# 用 server 镜像里自带的 zabbix_sender，避免再拉一个镜像
SENDER_IMAGE="${SENDER_IMAGE:-zabbix/zabbix-server-pgsql:alpine-7.0-latest}"

REPLICA_CONTAINER="${REPLICA_CONTAINER:-node2-db}"
BACKUP_DIR="${BACKUP_DIR:-/opt/ops/backup/mysql}"

LOG_DIR="/opt/ops/logs/monitor"
LOG="$LOG_DIR/host_checks.log"
DRY_RUN=0
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1

mkdir -p "$LOG_DIR"

log() { echo "[$(date '+%F %T')] $*" >> "$LOG"; }

# 日志超过 5MB 就留最后 1000 行 —— cron 跑一年不截断会写满磁盘
if [[ -f "$LOG" ]] && [[ $(stat -c%s "$LOG" 2>/dev/null || echo 0) -gt 5242880 ]]; then
    tail -1000 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"
fi

# ---------------- 1. MySQL 主从状态 ----------------
# 默认值就是「取不到」：-1 表示未知，0 表示复制正常但延迟未知
LAG=-1
RUNNING=0

if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "$REPLICA_CONTAINER"; then
    # ★ 从容器环境变量里读密码，不在脚本里硬编码。
    #   这样改 compose 里的密码，脚本不用跟着改。
    DB_PASS=$(docker inspect "$REPLICA_CONTAINER" \
                --format '{{range .Config.Env}}{{println .}}{{end}}' 2>/dev/null \
              | sed -n 's/^MYSQL_ROOT_PASSWORD=//p' | head -1)

    if [[ -n "$DB_PASS" ]]; then
        # ★★ 这里绝对不能加 -N -B ★★
        #   -B(batch) 会强制「一行一条记录、字段 tab 分隔」，它把 \G 请求的
        #   垂直输出格式**覆盖**掉了。于是 STATUS 变成一整行裸值，
        #   里面没有任何 "Replica_IO_Running:" 字样 → 下面三条 sed 全部匹配失败
        #   → IO/SQL 为空 → running=0 lag=-1（假故障）。
        #
        #   这个坑最阴的地方是「不报错」：退出码 0，命令成功，只是悄悄取不到。
        #   手动敲 mysql -e 'SHOW REPLICA STATUS\G' 一切正常，加了 -B 才坏，
        #   所以排查时很容易怀疑密码、网络、复制状态，就是不怀疑参数。
        #   （docs/08 第 20 坑）
        STATUS=$(docker exec -e MYSQL_PWD="$DB_PASS" "$REPLICA_CONTAINER" \
                 mysql -uroot -e 'SHOW REPLICA STATUS\G' 2>/dev/null)

        # ★ 字段名在 8.0.23 改过一次（Slave_* → Replica_*，Master → Source），
        #   必须两个名字都认。只认新名字的话：
        #     - 旧版本上 IO/SQL 取空 → running 恒为 0 → 假告警
        #     - 旧版本上延迟取空 → lag 恒为 -1 → 真故障不告警
        #   这就是 docs/08 第 7 坑（health_check.sh 里同一个错误），
        #   所以这里用 (Replica|Slave) / (Source|Master) 一次覆盖两代。
        IO=$(echo "$STATUS"  | sed -nE 's/^ *(Replica|Slave)_IO_Running: *//p'  | head -1)
        SQL=$(echo "$STATUS" | sed -nE 's/^ *(Replica|Slave)_SQL_Running: *//p' | head -1)
        L=$(echo "$STATUS"   | sed -nE 's/^ *Seconds_Behind_(Source|Master): *//p' | head -1)

        [[ "$IO" == "Yes" && "$SQL" == "Yes" ]] && RUNNING=1
        [[ "$L" =~ ^[0-9]+$ ]] && LAG=$L

        [[ "$IO" != "Yes" || "$SQL" != "Yes" ]] && \
            log "WARN 复制未双通: IO=$IO SQL=$SQL"
    else
        log "WARN 取不到 $REPLICA_CONTAINER 的 MYSQL_ROOT_PASSWORD"
    fi
else
    log "WARN 容器 $REPLICA_CONTAINER 不在运行（lag/running 记为 -1/0）"
fi

# ---------------- 2. 最新备份文件的年龄 ----------------
# 没备份文件时给 999999，保证一定越过任何阈值 —— 「没备份」不该看起来像「刚备份过」
BACKUP_AGE=999999
if [[ -d "$BACKUP_DIR" ]]; then
    LATEST=$(ls -t "$BACKUP_DIR"/mysql_*.sql.gz 2>/dev/null | head -1)
    if [[ -n "$LATEST" ]]; then
        MTIME=$(stat -c %Y "$LATEST" 2>/dev/null || echo 0)
        [[ "$MTIME" -gt 0 ]] && BACKUP_AGE=$(( $(date +%s) - MTIME ))
    else
        log "WARN $BACKUP_DIR 下没有 mysql_*.sql.gz"
    fi
else
    log "WARN 备份目录不存在: $BACKUP_DIR"
fi

# ---------------- 3. 推送 ----------------
if [[ $DRY_RUN -eq 1 ]]; then
    echo "hostname=$ZBX_HOSTNAME"
    echo "shop.repl.lag     = $LAG"
    echo "shop.repl.running = $RUNNING"
    echo "shop.backup.age   = $BACKUP_AGE"
    exit 0
fi

# --network host：脚本在宿主机跑，sender 容器要能访问 127.0.0.1:10051
# ★★ zabbix_sender 的 -k/-o 只能出现一次！★★
#   写成 `-k a -o 1 -k b -o 2` 会直接被参数解析器拒绝：
#       option "-k" or "--key" specified multiple times
#   要一次推多个 key，必须改用「输入文件」格式，每行一条：`主机名 key 值`，
#   再用 -i - 从 stdin 读（docker 侧要加 -i 保持 stdin 打开）。
#   注意输入文件里**不写 -s**：主机名在每行首列，-s 会被忽略。
OUT=$(printf '%s %s %s\n' \
        "$ZBX_HOSTNAME" shop.repl.lag     "$LAG" \
        "$ZBX_HOSTNAME" shop.repl.running "$RUNNING" \
        "$ZBX_HOSTNAME" shop.backup.age   "$BACKUP_AGE" \
      | docker run --rm -i --network host \
          --entrypoint zabbix_sender "$SENDER_IMAGE" \
          -z "$ZBX_SERVER" -p "$ZBX_PORT" -i - 2>&1)
RC=$?

# zabbix_sender 成功时输出：processed: 3; failed: 0; total: 3; seconds spent: ...
# ★ 只看退出码不够：部分失败时也可能返回 0，必须同时检查 failed: 0
if [[ $RC -eq 0 ]] && echo "$OUT" | grep -q 'failed: 0'; then
    log "OK   lag=$LAG running=$RUNNING backup_age=$BACKUP_AGE"
    # ★ 成功也往 stdout 打一行。
    #   脚本原本「全静默，只写日志」，cron 跑是干净了，但手动执行时一片空白，
    #   连「到底跑没跑」都看不出来 —— 配合命令行里的 && 就是彻底黑屏。
    #   打一行到终端不影响 cron（crontab 里会把 stdout 重定向掉）。
    echo "OK   lag=$LAG running=$RUNNING backup_age=$BACKUP_AGE"
else
    log "ERR  推送失败 rc=$RC"
    while IFS= read -r line; do
        [[ -n "$line" ]] && log "     $line"
    done <<< "$OUT"
    # 常见原因提示，免得上服务器才发现
    echo "$OUT" | grep -qi 'connection refused' && \
        log "     提示：zabbix-server 的 10051 没在宿主机监听？docker ps | grep zbx-server"
    echo "$OUT" | grep -qi 'not found\|no such host' && \
        log "     提示：ZBX_HOSTNAME 与界面里的 Host name 不一致（trapper 靠名字匹配）"

    # ★ 失败时把原因打到 stderr，别让人只看到一个空白终端
    {
        echo "[推送失败 rc=$RC] 完整日志：$LOG"
        echo "$OUT" | sed 's/^/    /'
    } >&2
    exit 1
fi
