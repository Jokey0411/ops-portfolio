#!/usr/bin/env bash
# =============================================================
#  告警通知：钉钉 / 飞书 / 邮件
#  用法：bash notify.sh "标题" "正文" [warning|critical]
#  配置：把下面的环境变量写进 /opt/ops/.env.notify
#    DINGTALK_WEBHOOK="https://oapi.dingtalk.com/robot/send?access_token=xxx"
#    DINGTALK_SECRET="SECxxxx"      # 加签模式才需要
#    DINGTALK_KEYWORD="告警"        # 关键词模式才需要（内容里必须出现这个词）
#    FEISHU_WEBHOOK="https://open.feishu.cn/open-apis/bot/v2/hook/xxx"
#    MAIL_TO="you@qq.com"           # 邮件需要装 msmtp，见文件底部说明
# =============================================================

TITLE="${1:-告警}"
BODY="${2:-}"
LEVEL="${3:-warning}"          # warning / critical
HOST=$(hostname)
TS=$(date '+%Y-%m-%d %H:%M:%S')

CONF="${NOTIFY_CONF:-/opt/ops/.env.notify}"
if [[ -f "$CONF" ]]; then
    . "$CONF"
else
    echo "[notify] 配置文件不存在：$CONF"
fi

# ★ 关键词模式兜底：钉钉机器人选「自定义关键词」时，消息内容必须含该词，
#   否则钉钉返回 310000 keywords not in content。不同告警标题不一定含关键词，
#   所以这里统一塞进标题里。
[[ -n "${DINGTALK_KEYWORD:-}" ]] && TITLE="${TITLE} ${DINGTALK_KEYWORD}"

FULL="[${LEVEL^^}] ${TITLE}
主机: ${HOST}
时间: ${TS}
${BODY}"

SENT=0
CONFUSED=0   # 配了渠道但发不出去
HAVE_CONF=0

# ---------- 钉钉 ----------
if [[ -n "${DINGTALK_WEBHOOK:-}" ]]; then
    HAVE_CONF=1
    URL="$DINGTALK_WEBHOOK"
    # 加签模式
    if [[ -n "${DINGTALK_SECRET:-}" ]]; then
        TS_MS=$(date +%s%3N)
        [[ "$TS_MS" =~ ^[0-9]+$ ]] || TS_MS=$(( $(date +%s) * 1000 ))
        # 算法：HMAC-SHA256(key=secret, data="timestamp\nsecret") 再 base64
        SIGN=$(printf '%s\n%s' "$TS_MS" "$DINGTALK_SECRET" \
               | openssl dgst -sha256 -hmac "$DINGTALK_SECRET" -binary \
               | base64 | tr -d '\n')
        # base64 里的 + / = 必须 URL 编码，否则签名对不上
        SIGN_ENC=$(printf '%s' "$SIGN" | python3 -c \
            "import urllib.parse,sys;print(urllib.parse.quote(sys.stdin.read(),safe=''))" 2>/dev/null \
            || printf '%s' "$SIGN" | sed -e 's/+/%2B/g' -e 's/\//%2F/g' -e 's/=/%3D/g')
        URL="${URL}&timestamp=${TS_MS}&sign=${SIGN_ENC}"
    fi
    PAYLOAD=$(python3 - "$TITLE" "$FULL" <<'PY'
import json, sys
print(json.dumps({
    "msgtype": "text",
    "text": {"content": "【%s】\n%s" % (sys.argv[1], sys.argv[2])}
}, ensure_ascii=False))
PY
)
    RESP=$(curl -sS -m 8 -H 'Content-Type: application/json' -d "$PAYLOAD" "$URL" 2>&1)
    if printf '%s' "$RESP" | grep -q '"errcode":0'; then
        echo "[notify] 钉钉发送成功"; SENT=1
    else
        # ★ 把钉钉返回的 errcode/errmsg 打出来，不看这个永远不知道为什么失败
        echo "[notify] 钉钉发送失败：$(printf '%s' "$RESP" | head -c 400)"
        case "$RESP" in
            *310000*) echo "[notify]   310000 → 关键词不匹配 或 签名错误（检查 DINGTALK_KEYWORD / DINGTALK_SECRET）";;
            *300001*) echo "[notify]   300001 → access_token 无效（webhook 复制错了）";;
            *130101*) echo "[notify]   130101 → 发送频率超限（20 条/分钟）";;
            *"connect"*|*"timed out"*|*"Could not resolve"*) echo "[notify]   网络层失败：服务器出不了外网";;
        esac
        CONFUSED=1
    fi
fi

# ---------- 飞书 ----------
if [[ -n "${FEISHU_WEBHOOK:-}" ]]; then
    HAVE_CONF=1
    PAYLOAD=$(python3 - "$TITLE" "$FULL" <<'PY'
import json, sys
print(json.dumps({
    "msg_type": "text",
    "content": {"text": "【%s】\n%s" % (sys.argv[1], sys.argv[2])}
}, ensure_ascii=False))
PY
)
    RESP=$(curl -sS -m 8 -H 'Content-Type: application/json' -d "$PAYLOAD" "$FEISHU_WEBHOOK" 2>&1)
    if printf '%s' "$RESP" | grep -q '"StatusCode":0\|"code":0'; then
        echo "[notify] 飞书发送成功"; SENT=1
    else
        echo "[notify] 飞书发送失败：$(printf '%s' "$RESP" | head -c 400)"
        CONFUSED=1
    fi
fi

# ---------- 邮件（需要 msmtp，可选）----------
if [[ -n "${MAIL_TO:-}" ]] && command -v msmtp &>/dev/null; then
    HAVE_CONF=1
    printf 'Subject: %s\n\n%s\n' "$TITLE" "$FULL" | msmtp "$MAIL_TO" && {
        echo "[notify] 邮件发送成功"; SENT=1
    } || { echo "[notify] 邮件发送失败"; CONFUSED=1; }
fi

# ---------- 兜底：至少落到本地告警日志 ----------
mkdir -p /opt/ops/logs
echo "${TS} [${LEVEL}] ${TITLE} | ${BODY}" >> /opt/ops/logs/alarm.log

if [[ $SENT -eq 0 ]]; then
    if [[ $HAVE_CONF -eq 1 ]]; then
        # ★ 「配了但发不出去」和「根本没配」是两回事，文案不能混
        echo "[notify] ✘ 已配置告警渠道但发送失败，原因见上方；已写入 /opt/ops/logs/alarm.log"
        exit 1
    else
        echo "[notify] ⚠ 未配置任何告警渠道（$CONF 里没有 DINGTALK_WEBHOOK / FEISHU_WEBHOOK / MAIL_TO），仅写入本地日志"
    fi
fi
exit 0
