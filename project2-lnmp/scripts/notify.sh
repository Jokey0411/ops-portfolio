#!/usr/bin/env bash
# =============================================================
#  告警通知：钉钉 / 飞书 / 邮件
#  用法：bash notify.sh "标题" "正文" [warning|critical]
#  配置：把下面的环境变量写进 /opt/ops/.env.notify
#    DINGTALK_WEBHOOK="https://oapi.dingtalk.com/robot/send?access_token=xxx"
#    DINGTALK_SECRET="SECxxxx"      # 加签模式才需要
#    FEISHU_WEBHOOK="https://open.feishu.cn/open-apis/bot/v2/hook/xxx"
#    MAIL_TO="you@qq.com"           # 邮件需要装 msmtp，见文件底部说明
# =============================================================

TITLE="${1:-告警}"
BODY="${2:-}"
LEVEL="${3:-warning}"          # warning / critical
HOST=$(hostname)
TS=$(date '+%Y-%m-%d %H:%M:%S')

CONF="${NOTIFY_CONF:-/opt/ops/.env.notify}"
[[ -f "$CONF" ]] && . "$CONF"

FULL="[${LEVEL^^}] ${TITLE}
主机: ${HOST}
时间: ${TS}
${BODY}"

SENT=0

# ---------- 钉钉 ----------
if [[ -n "${DINGTALK_WEBHOOK:-}" ]]; then
    URL="$DINGTALK_WEBHOOK"
    # 加签模式
    if [[ -n "${DINGTALK_SECRET:-}" ]]; then
        TS_MS=$(date +%s%3N)
        SIGN=$(printf '%s\n%s' "$TS_MS" "$DINGTALK_SECRET" | openssl dgst -sha256 -hmac "$DINGTALK_SECRET" -binary | base64)
        URL="${URL}&timestamp=${TS_MS}&sign=$(python3 -c "import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1]))" "$SIGN" 2>/dev/null || echo "$SIGN")"
    fi
    PAYLOAD=$(python3 - "$TITLE" "$FULL" <<'PY'
import json, sys
print(json.dumps({
    "msgtype": "text",
    "text": {"content": "【%s】\n%s" % (sys.argv[1], sys.argv[2])}
}, ensure_ascii=False))
PY
)
    if curl -sS -m 8 -H 'Content-Type: application/json' -d "$PAYLOAD" "$URL" 2>/dev/null | grep -q '"errcode":0'; then
        echo "[notify] 钉钉发送成功"; SENT=1
    else
        echo "[notify] 钉钉发送失败"
    fi
fi

# ---------- 飞书 ----------
if [[ -n "${FEISHU_WEBHOOK:-}" ]]; then
    PAYLOAD=$(python3 - "$TITLE" "$FULL" <<'PY'
import json, sys
print(json.dumps({
    "msg_type": "text",
    "content": {"text": "【%s】\n%s" % (sys.argv[1], sys.argv[2])}
}, ensure_ascii=False))
PY
)
    if curl -sS -m 8 -H 'Content-Type: application/json' -d "$PAYLOAD" "$FEISHU_WEBHOOK" 2>/dev/null | grep -q '"StatusCode":0\|"code":0'; then
        echo "[notify] 飞书发送成功"; SENT=1
    else
        echo "[notify] 飞书发送失败"
    fi
fi

# ---------- 邮件（需要 msmtp，可选）----------
if [[ -n "${MAIL_TO:-}" ]] && command -v msmtp &>/dev/null; then
    printf 'Subject: %s\n\n%s\n' "$TITLE" "$FULL" | msmtp "$MAIL_TO" && {
        echo "[notify] 邮件发送成功"; SENT=1
    } || echo "[notify] 邮件发送失败"
fi

# ---------- 兜底：至少落到本地告警日志 ----------
mkdir -p /opt/ops/logs
echo "${TS} [${LEVEL}] ${TITLE} | ${BODY}" >> /opt/ops/logs/alarm.log

if [[ $SENT -eq 0 ]]; then
    echo "[notify] 未配置任何告警渠道，仅写入本地日志 /opt/ops/logs/alarm.log"
fi
exit 0
