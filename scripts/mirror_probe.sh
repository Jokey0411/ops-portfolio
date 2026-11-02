#!/usr/bin/env bash
# =============================================================
#  镜像源探测脚本 —— 找出这台机器上到底哪个源能拉到镜像
#  用法：bash scripts/mirror_probe.sh
#  只读探测，不改任何配置（除了临时拉一个 hello-world）
# =============================================================
set -uo pipefail

GRN='\033[32m'; RED='\033[31m'; YEL='\033[33m'; NC='\033[0m'
ok()   { echo -e "${GRN}  ✔ $*${NC}"; }
bad()  { echo -e "${RED}  ✘ $*${NC}"; }
info() { echo -e "${YEL}  → $*${NC}"; }

command -v docker &>/dev/null || { echo "docker 没装，先跑 00-init-server.sh"; exit 1; }

echo "=============================================="
echo " Docker 镜像源探测 | $(date '+%F %T')"
echo "=============================================="

# ---------- 1. 当前生效的加速源 ----------
echo ""
echo "[1/4] 当前生效的 registry-mirrors"
docker info 2>/dev/null | grep -A8 "Registry Mirrors" | sed 's/^/  /'

# ---------- 2. 基础连通性：不带任何前缀，看 mirror 是否工作 ----------
echo ""
echo "[2/4] 测试：直接拉官方镜像（依赖 registry-mirrors）"
for IMG in "nginx:alpine" "mysql:8.0" "python:3.11-alpine" "php:8.2-fpm-alpine"; do
    if timeout 90 docker pull "$IMG" &>/dev/null; then
        ok "$IMG 拉取成功（mirror 生效，后面都不用改）"
    else
        bad "$IMG 拉取失败"
    fi
done

# ---------- 3. 前缀式直连源：挨个试 ----------
echo ""
echo "[3/4] 测试：前缀式镜像源（能通的话就改 compose 里的镜像名）"
# 候选源列表，可自行增删
CANDIDATES=(
    "ccr.ccs.tencentyun.com"
    "docker.1ms.run"
    "docker.xuanyuan.me"
    "dockerpull.org"
    "hub.rat.dev"
    "dockerhub.icu"
)
WORKING=()
for REG in "${CANDIDATES[@]}"; do
    # 先用 HTTP 探一下 /v2/，200 或 401 都算"通"（401 是未认证的标准响应）
    CODE=$(timeout 15 curl -s -o /dev/null -w "%{http_code}" "https://${REG}/v2/" 2>/dev/null)
    if [[ "$CODE" == "200" || "$CODE" == "401" ]]; then
        info "${REG} HTTP ${CODE}（可达），实测拉取中..."
        if timeout 90 docker pull "${REG}/library/nginx:alpine" &>/dev/null; then
            ok "${REG} 可用 ✔✔"
            WORKING+=("${REG}")
        else
            bad "${REG} 可达但拉不动（多半没同步 library 命名空间）"
        fi
    else
        bad "${REG} 不可达（HTTP ${CODE:-超时}）"
    fi
done

# ---------- 4. 结论与下一步命令 ----------
echo ""
echo "[4/4] 结论"
if [[ ${#WORKING[@]} -gt 0 ]]; then
    REG="${WORKING[0]}"
    ok "推荐源：${REG}"
    echo ""
    echo "  把两个 compose 里的镜像名加上前缀（执行前会自动备份）："
    echo ""
    cat <<EOS
    cd /opt/ops
    for f in project1-cluster/docker-compose.yml project2-lnmp/docker-compose.yml; do
      cp -a "\$f" "\$f.bak.\$(date -I)"
      sed -i -E "s#image: (nginx|mysql|python|php|redis):#image: ${REG}/library/\\1:#" "\$f"
    done
    grep -n "image:" project1-cluster/docker-compose.yml project2-lnmp/docker-compose.yml
EOS
    echo ""
    echo "  Dockerfile 里的 FROM 也要改（build 时会用到）："
    echo "    sed -i 's#^FROM #FROM ${REG}/library/#' project1-cluster/app/Dockerfile project2-lnmp/php/Dockerfile"
    echo ""
    echo "  改完验证："
    echo "    cd project1-cluster && docker compose config >/dev/null && echo 'compose 语法 OK'"
else
    bad "全部候选源都不可用"
    echo ""
    echo "  最后的办法 —— 让 docker 走 HTTP 代理（如果你有可用的代理）："
    cat <<'EOS'
    mkdir -p /etc/systemd/system/docker.service.d
    cat > /etc/systemd/system/docker.service.d/proxy.conf <<'PROXY'
[Service]
Environment="HTTP_PROXY=http://127.0.0.1:7890"
Environment="HTTPS_PROXY=http://127.0.0.1:7890"
PROXY
    systemctl daemon-reload && systemctl restart docker
    docker pull nginx:alpine        # 再试
EOS
    echo ""
    echo "  代理端口按你实际情况改（Clash 7890 / v2rayN 10809）。"
    echo "  用完想取消：rm -f /etc/systemd/system/docker.service.d/proxy.conf && systemctl daemon-reload && systemctl restart docker"
fi

echo ""
echo "=============================================="
echo " 常用诊断命令备查："
echo "   docker info | grep -A8 'Registry Mirrors'   # 看加速源有没有生效"
echo "   docker pull nginx:alpine                    # 不带 tag 拉 latest，判断是 tag 问题还是源问题"
echo "   curl -sI https://mirror.ccs.tencentyun.com/v2/   # 直连探测"
echo "   journalctl -u docker -n 30 --no-pager       # 看 daemon 侧报错"
echo "=============================================="
