#!/usr/bin/env bash
# =============================================================
#  服务器初始化脚本 —— OpenCloudOS / 2核2G 轻量服务器
#  作用：装 Docker、配 firewalld、内核参数、swap、目录骨架
#  用法：bash 00-init-server.sh 2>&1 | tee /var/log/init-server.log
#  幂等：可重复执行
# =============================================================
set -uo pipefail

RED='\033[31m'; GRN='\033[32m'; YEL='\033[33m'; NC='\033[0m'
log()  { echo -e "${GRN}[$(date '+%H:%M:%S')] ✔${NC} $*"; }
warn() { echo -e "${YEL}[$(date '+%H:%M:%S')] ⚠${NC} $*"; }
err()  { echo -e "${RED}[$(date '+%H:%M:%S')] ✘${NC} $*"; }

[[ $EUID -ne 0 ]] && { err "请用 root 执行：sudo bash $0"; exit 1; }

echo "=============================================="
echo " 服务器初始化 | $(date '+%Y-%m-%d %H:%M:%S')"
echo "=============================================="

# ---------- 0. 环境探测 ----------
. /etc/os-release
log "系统：${PRETTY_NAME:-unknown}"
log "内核：$(uname -r)"
log "内存：$(free -h | awk '/^Mem:/{print $2}')  磁盘可用：$(df -h / | awk 'NR==2{print $4}')"
OS_MAJOR=$(echo "${VERSION_ID}" | cut -d. -f1)

# ---------- 1. 时间同步（主从复制、日志排查的前提）----------
log "[1/9] 配置时间同步 chrony"
if ! command -v chronyc &>/dev/null; then
    dnf install -y chrony -q || warn "chrony 安装失败，请手动处理"
fi
systemctl enable --now chronyd &>/dev/null && {
    chronyc -a makestep &>/dev/null
    log "  当前时间：$(date '+%F %T') | 时区：$(timedatectl show -p Timezone --value)"
} || warn "chronyd 启动失败"

# ---------- 2. Swap（2G 内存必加，否则 mysqldump 时必 OOM）----------
log "[2/9] 配置 Swap"
if swapon --show | grep -q 'swapfile'; then
    log "  Swap 已存在：$(swapon --show | awk '/swapfile/{print $2}')"
else
    if [[ $(free -m | awk '/^Mem:/{print $2}') -le 4096 ]]; then
        SWAP_SIZE=2048
    else
        SWAP_SIZE=1024
    fi
    fallocate -l ${SWAP_SIZE}M /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count=${SWAP_SIZE} status=none
    chmod 600 /swapfile
    mkswap /swapfile &>/dev/null
    swapon /swapfile
    grep -q '/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
    log "  已创建 ${SWAP_SIZE}M swap"
fi

# ---------- 3. 内核参数（简历："配置内核参数"）----------
log "[3/9] 写入内核参数 /etc/sysctl.d/99-ops.conf"
cat > /etc/sysctl.d/99-ops.conf <<'EOF'
# ---- 网络：高并发连接回收与队列 ----
net.ipv4.ip_forward = 1                 # Docker 跨节点网络转发必需
net.ipv4.tcp_syncookies = 1             # 防 SYN Flood
net.ipv4.tcp_tw_reuse = 1               # 复用 TIME_WAIT  socket
net.ipv4.tcp_fin_timeout = 30           # FIN_WAIT 超时，默认 60 太长
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_max_syn_backlog = 8192
net.core.somaxconn = 65535              # 默认 128，Nginx 高并发必调
net.core.netdev_max_backlog = 5000
net.ipv4.ip_local_port_range = 1024 65535

# ---- 文件句柄 ----
fs.file-max = 655350

# ---- 内存：2G 小内存机器，尽量少用 swap，但保留 OOM 缓冲 ----
vm.swappiness = 10
vm.overcommit_memory = 1                # MySQL 申请大内存时不被拒绝
EOF
sysctl --system &>/dev/null
log "  ip_forward=$(sysctl -n net.ipv4.ip_forward)  somaxconn=$(sysctl -n net.core.somaxconn)  file-max=$(sysctl -n fs.file-max)"

# ---------- 4. 文件句柄限制 ----------
log "[4/9] 配置 ulimit"
cat > /etc/security/limits.d/99-ops.conf <<'EOF'
*       soft    nofile  65535
*       hard    nofile  65535
*       soft    nproc   65535
*       hard    nproc   65535
root    soft    nofile  65535
root    hard    nofile  65535
EOF
log "  已写入 limits（重新登录后生效）"

# ---------- 5. 安装 Docker ----------
log "[5/9] 安装 Docker"
install_docker_official_repo() {
    dnf install -y dnf-plugins-core -q 2>/dev/null
    cat > /etc/yum.repos.d/docker-ce.repo <<EOF
[docker-ce-stable]
name=Docker CE Stable
baseurl=https://mirrors.cloud.tencent.com/docker-ce/linux/centos/${OS_MAJOR}/\$basearch/stable
enabled=1
gpgcheck=1
gpgkey=https://mirrors.cloud.tencent.com/docker-ce/linux/centos/gpg
EOF
    dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -q
}

if command -v docker &>/dev/null; then
    log "  Docker 已安装：$(docker --version 2>/dev/null | head -1)"
else
    install_docker_official_repo || {
        warn "  镜像源安装失败，回退到官方安装脚本"
        curl -fsSL https://get.docker.com | bash -s docker --mirror Aliyun
    }
fi

if ! command -v docker &>/dev/null; then
    err "Docker 安装失败！请检查网络后手动安装："
    err "  curl -fsSL https://get.docker.com | bash"
    exit 1
fi

# ---------- 6. Docker 镜像加速（国内拉 Docker Hub 慢/失败是常态）----------
log "[6/9] 配置 Docker 镜像加速"
mkdir -p /etc/docker
cat > /etc/docker/daemon.json <<'EOF'
{
  "registry-mirrors": [
    "https://mirror.ccs.tencentyun.com",
    "https://docker.1ms.run",
    "https://docker.xuanyuan.me"
  ],
  "log-driver": "json-file",
  "log-opts": { "max-size": "20m", "max-file": "3" },
  "live-restore": true,
  "exec-opts": ["native.cgroupdriver=systemd"],
  "storage-driver": "overlay2"
}
EOF
# 限制 journald，避免日志吃光磁盘
mkdir -p /etc/systemd/journald.conf.d
cat > /etc/systemd/journald.conf.d/99-ops.conf <<'EOF'
[Journal]
SystemMaxUse=200M
RuntimeMaxUse=100M
MaxRetentionSec=7day
EOF

systemctl daemon-reload
systemctl enable --now docker &>/dev/null
sleep 3
log "  Docker 状态：$(systemctl is-active docker)"
log "  Compose 插件：$(docker compose version 2>/dev/null | head -1 || echo '未安装')"

# 验证镜像拉取（这一步能提前暴露网络问题）
if timeout 120 docker pull hello-world:latest &>/dev/null; then
    log "  镜像拉取测试：通过"
else
    warn "  镜像拉取失败！大概率是 registry-mirrors 全部失效。"
    warn "  备选方案（腾讯云镜像仓库，走内网，最稳）："
    warn "    docker pull ccr.ccs.tencentyun.com/library/nginx:1.25-alpine"
    warn "    然后把 compose 里的镜像地址改成 ccr.ccs.tencentyun.com/library/xxx"
fi

# ---------- 7. 防火墙（简历："配置 firewalld 安全策略"）----------
log "[7/9] 配置 firewalld"
if ! command -v firewall-cmd &>/dev/null; then
    dnf install -y firewalld -q || warn "firewalld 安装失败"
fi
systemctl enable --now firewalld &>/dev/null

CURRENT_SSH_PORT=$(ss -tlnp 2>/dev/null | grep sshd | awk '{print $4}' | sed 's/.*://' | head -1)
CURRENT_SSH_PORT=${CURRENT_SSH_PORT:-22}
log "  检测到 SSH 端口：${CURRENT_SSH_PORT}（放通，防把自己锁在外面）"

firewall-cmd --permanent --add-port=${CURRENT_SSH_PORT}/tcp &>/dev/null
firewall-cmd --permanent --add-port=80/tcp    &>/dev/null   # 项目一 LB
firewall-cmd --permanent --add-port=8080/tcp &>/dev/null   # 项目二 LNMP
firewall-cmd --permanent --add-port=8400/tcp &>/dev/null   # LB 状态页
firewall-cmd --reload &>/dev/null
log "  已放通端口：$(firewall-cmd --list-ports)"
log "  默认区域：$(firewall-cmd --get-default-zone)"

# ---------- 8. 目录骨架 ----------
log "[8/9] 创建目录骨架"
mkdir -p /opt/ops/{project1-cluster,project2-lnmp,backup,logs}
mkdir -p /opt/ops/backup/{mysql,code}
mkdir -p /opt/ops/logs/{scripts,nginx}
log "  /opt/ops 就绪"

# ---------- 9. 常用排查工具 ----------
log "[9/9] 安装排查工具（这些是简历里"抓包/诊断"的底气）"
dnf install -y -q \
    tcpdump net-tools lsof strace sysstat iotop htop \
    curl wget vim tar gzip bzip2 jq rsync telnet bind-utils \
    >/dev/null 2>&1 || warn "部分工具安装失败，不影响主流程"
for t in tcpdump lsof ss iostat jq; do
    command -v $t &>/dev/null && log "  ✔ $t" || warn "  ✘ $t 未安装"
done

# ---------- 完成 ----------
cat <<EOF

==============================================
 初始化完成
==============================================
 系统信息 : ${PRETTY_NAME}
 内存     : $(free -h | awk '/^Mem:/{printf "%s / 可用 %s", $2, $7}')
 Swap     : $(swapon --show --noheadings 2>/dev/null | awk '{print $3}' || echo '无')
 Docker   : $(docker --version 2>/dev/null | head -1)
 防火墙   : $(systemctl is-active firewalld)  放通端口: $(firewall-cmd --list-ports)

 下一步:
   cd /opt/ops/project1-cluster
   bash scripts/../README.md 里的步骤依次执行

 ⚠ 提醒：如果服务器重启过，请重新登录让 ulimit 生效
EOF
