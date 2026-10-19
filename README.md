# 两个项目在一台轻量服务器上的落地方案 · 执行手册

> 目标：把简历上「多机模拟 Web 业务集群」和「Docker Compose 部署 LNMP」这两段，
> 变成你亲手跑过、能被追问到底的真实经历。
>
> 环境：腾讯云轻量应用服务器 **2 核 2G**，**OpenCloudOS**
> 用法：**照着敲就行**。每条命令后面都写了"你应该看到什么"和"对不上怎么办"。

> **本文件是「执行手册」，不是仓库门面。**
> 给别人看 / 推到 GitHub 时，用 **`GitHub首页README.md`**（那份才是对外的门面，
> 含架构图、设计取舍、验收状态表）。
> 相关文档：`docs/架构说明.md`（为什么这么设计）、`docs/验收记录.md`（跑一项填一项）。

---

# 第一部分：动手之前必须先想明白的三件事

## 1. 一台机器怎么做「多机集群」

简历写「2 台 CentOS 节点」，但你只有一台云主机：

| 方案 | 可行性 | 结论 |
|---|---|---|
| 云服务器里跑 KVM/VirtualBox 虚拟机 | ❌ 轻量服务器**不支持嵌套虚拟化**，`kvm-ok` 必然失败 | 放弃 |
| Docker 容器模拟 2 个节点 | ✅ 独立 hostname、独立网络命名空间、独立 rootfs | **采用** |
| 多买两台云主机 | 💰 成本翻倍 | 放弃 |

**面试必答题（背下来）**：
> "我只有一台 2C2G 云主机，用 Docker 的网络命名空间隔离出两个独立节点，
> 每个节点有独立 IP、独立 hostname、独立 MySQL 实例，前面挂 Nginx 做负载均衡。
> 这种模拟能覆盖集群运维里 90% 的排查场景——网络不通、端口冲突、主从延迟、数据卷权限——
> 但内核参数、磁盘 IO 这类宿主机级别的问题是共享的，这是这种方案的边界。"

## 2. 2G 内存预算表（别把机器跑崩）

| 组件 | 默认占用 | 裁剪后 | 裁剪手段 |
|---|---|---|---|
| OpenCloudOS 系统 | ~250MB | ~250MB | — |
| dockerd | ~90MB | ~90MB | — |
| MySQL 8.0 × 2 | ~450MB × 2 | **~220MB × 2** | `innodb_buffer_pool_size=96M`、`performance_schema=OFF`、`table_open_cache=200` |
| Nginx × 3 | ~15MB × 3 | 同左 | alpine 镜像 |
| Python 业务进程 × 2 | ~45MB × 2 | ~35MB × 2 | alpine |
| **项目一合计** | — | **≈ 1.05G** | 余量约 700MB |
| LNMP（项目二） | — | **≈ 0.75G** | 只有 1 个 MySQL |

**三条硬性规则**
1. **两个项目绝不同时运行** —— 先 `docker compose down` 再起下一个。
2. **必须加 2G swap** —— 否则 `mysqldump` 时会被内核 OOM 杀掉。
3. **`free -h` 的 available 低于 200MB 就要动手处理**。

## 3. 目录结构

```
ops-portfolio/
├── 00-init-server.sh              # 服务器初始化（D1 第一件事）
├── README.md                      # 本文件
├── env.notify.example             # 告警配置示例
├── project1-cluster/              # 项目一
│   ├── README.md                  # 详细步骤 + 排错 + 面试点
│   ├── docker-compose.yml         # 4 网 7 容器
│   ├── nginx/{lb.conf,node.conf}
│   ├── app/{Dockerfile,app.py}
│   ├── mysql/{master.cnf,slave.cnf}
│   ├── sql/init.sql
│   ├── scripts/{backup.sh,health_check.sh,notify.sh,setup_replication.sh,failover_drill.sh}
│   └── docs/{故障演练手册.md,故障复盘模板.md}
├── project2-lnmp/                 # 项目二
│   ├── README.md
│   ├── docker-compose.yml
│   ├── php/{Dockerfile,php.ini}
│   ├── nginx/conf.d/default.conf
│   ├── mysql/conf/my.cnf
│   ├── sql/{schema.sql,gen_data.sql,optimize.sql}
│   ├── scripts/{mysql_backup.sh,restore_test.sh,bench.sh,notify.sh}
│   └── docs/SQL优化记录.md
└── interview/高频追问与答法.md  命令与SQL速查.md  Linux场景面试题库.md
```

---

# 第二部分：逐日执行手册

> 每一步的格式：**做什么 → 敲什么 → 应该看到什么 → 对不上怎么办**

---

## D0 · 准备（30 分钟，在腾讯云控制台和你的电脑上做）

### 步骤 0-1：确认/重装系统为 OpenCloudOS

腾讯云控制台 → 轻量应用服务器 → 你的实例 → **重装系统** → 应用镜像选「OpenCloudOS」（或系统镜像）。

> ⚠️ **不要选"宝塔面板""LNMP 一键包"这类应用镜像**。
> 它们会预装一堆服务占内存，还会占用 80/888 端口，跟我们的方案打架。
> 选纯净的 OpenCloudOS 系统镜像。

重装后拿到：**公网 IP**、**root 密码**（或密钥）。

### 步骤 0-2：★ 控制台防火墙放行端口（最容易漏的一步）

> 腾讯云轻量有**独立于系统之外的控制台防火墙**。
> 只配系统里的 `firewalld`，外网照样进不来——这是新手最常卡死的地方。

控制台 → 服务器详情 → **防火墙** → 添加规则：

| 应用类型 | 协议 | 端口 | 来源 |
|---|---|---|---|
| SSH | TCP | 22 | 你的 IP（或 0.0.0.0/0） |
| HTTP | TCP | 80 | 0.0.0.0/0 |
| 自定义 | TCP | 8080 | 0.0.0.0/0 |
| 自定义 | TCP | 8400 | 0.0.0.0/0 |

**验证方法**（先做这步，省得后面白排查）：
```bash
# 在你自己电脑上执行（不是服务器）
telnet 你的公网IP 22
# 或者
curl -m 5 -v http://你的公网IP
```
> 端口未放行时的表现：`curl` 一直卡住直到超时（不是"拒绝连接"，是被丢包）。

> ⚠️ **用 IP 访问，不要绑域名**。国内机房的 80 端口要绑域名的话会触发备案拦截，
> 直接用 `http://公网IP` 就没这个麻烦。等端口都通了再考虑域名的事。

### 步骤 0-3：登录服务器（先能登上去再谈别的）

**先用最快的方式登上去**（密码登录，控制台里能看到密码）：
```powershell
# 方式 A：PowerShell / CMD（Windows 10 之后自带 OpenSSH）
ssh root@你的公网IP

# 方式 B：腾讯云控制台 → 一键登录（WebShell），不用配本地环境

# 方式 C：Xshell / FinalShell（推荐长期用，能直接拖文件上传）
```

**然后配置密钥登录**（手上已有私钥文件，或想生成一对）：

👉 **完整步骤见 [`01-SSH密钥登录与安全加固.md`](01-SSH密钥登录与安全加固.md)**

流程摘要（详细命令都在那个文件里）：
```
1. Windows 修私钥权限         → icacls 两步（不做会报 Permissions are too open）
2. 公钥放上服务器             → scp 上传 + cat >> authorized_keys（最可靠）
3. 修服务器上 .ssh 权限       → chmod 700/600，SELinux 开着还要 restorecon
4. 测试密钥能登               → ssh -i key.pem root@IP，不用输密码就对了
5. 安全加固（可选但推荐）      → 改端口 + 禁密码 + firewalld 放行新端口
```

> ⚠️ **改 SSH 配置的铁律**：当前这个已连上的终端**绝对不能关**，
> 必须另开一个终端测试密钥登录成功后才允许关旧连接。
> 改崩了还有救：控制台 → 一键登录（VNC）进去改回来。

> 密钥登录 + 关掉密码认证 + 改非标准端口，这三件事做完，
> 简历上"配置 firewalld 安全策略"这条才算有真材实料。

### 步骤 0-4：上传文件

**方式 A：scp 上传压缩包（简单）**
```powershell
# 在你电脑上，PowerShell 里执行
cd C:\Users\34794\WorkBuddy\Linux
scp ops-portfolio.tar.gz root@你的公网IP:/root/
```
```bash
# 然后 ssh 到服务器执行
mkdir -p /opt/ops
tar xzf /root/ops-portfolio.tar.gz -C /opt/ops
ls /opt/ops
```

**方式 B：Git（推荐，改起来方便，面试时还能直接给人看仓库）**

> GitHub 从 2021-08 起**禁用了账号密码的 Git 认证**，直接 clone 会报
> `Password authentication is not supported`；改用 SSH 又会报 `Permission denied (publickey)`。
> **完整配置步骤见：`02-GitHub仓库与服务器同步.md`**（服务器生成 SSH 钥匙 / PAT 两种解法 + 排错表）。

最快路径（服务器上配好 GitHub 钥匙后）：
```bash
dnf install -y git
git clone git@github.com:Jokey0411/ops-portfolio.git /opt/ops
```

### 步骤 0-5：★ 修换行符 + 加执行权限（不做必踩坑）

```bash
cd /opt/ops

# Windows 编辑过的脚本带 CRLF，在 Linux 上会报 bad interpreter: /bin/bash^M
# 一次性清理掉
find . -name "*.sh" -exec sed -i 's/\r$//' {} \;

# 加执行权限
find . -name "*.sh" -exec chmod +x {} \;

# 验证
head -1 00-init-server.sh | od -c | head -2
# 应该看到 # ! / b i n / b a s h \n   —— 结尾是 \n 不是 \r \n
bash -n 00-init-server.sh && echo "语法 OK"
```

**预期输出**：
```
语法 OK
```
对不上 → 说明还有 CRLF 残留，重跑上面的 sed。

---

## D1 · 服务器初始化（40 分钟）

### 步骤 1-1：跑初始化脚本

```bash
cd /opt/ops
bash 00-init-server.sh 2>&1 | tee /var/log/init-server.log
```

脚本会自动做 9 件事：chrony 时间同步 → swap → 内核参数 → ulimit →
装 Docker → 镜像加速 → firewalld → 目录骨架 → 排查工具。

**耗时**：5~15 分钟（主要在装 Docker 和拉镜像测试）。

**尾部应该有这样的输出**：
```
==============================================
 初始化完成
==============================================
 系统信息 : OpenCloudOS 9
 内存     : 1.9Gi / 可用 1.6Gi
 Swap     : 2G
 Docker   : Docker version 26.x.x, build xxxxx
 防火墙   : active  放通端口: 22/tcp 80/tcp 8080/tcp 8400/tcp
```

### 步骤 1-2：逐项验证（别跳过，每项都要看到结果）

```bash
# 1) Docker 能用
docker --version
docker compose version
systemctl is-active docker              # 应为 active

# 2) Docker 能跑容器
docker run --rm hello-world             # 应打印 "Hello from Docker!"

# 3) Swap 生效
swapon --show
free -h | grep Swap                     # 应看到 2.0Gi

# 4) 内核参数生效
sysctl net.core.somaxconn               # = 65535
sysctl fs.file-max                      # = 655350
sysctl net.ipv4.ip_forward              # = 1

# 5) 防火墙
firewall-cmd --list-ports               # 22/tcp 80/tcp 8080/tcp 8400/tcp

# 6) 目录
ls /opt/ops                             # 应看到 project1-cluster project2-lnmp backup logs
```

### 步骤 1-3：卡住了怎么办

| 症状 | 原因 | 处理 |
|---|---|---|
| `Docker 安装失败` | 腾讯云 dnf 源里没有对应版本目录 | 见下方 A |
| `镜像拉取失败` | Docker Hub 国内访问受限 | 见下方 B |
| `docker: command not found` | 装完没重新登录 | 重新 ssh 登录，或 `export PATH=$PATH:/usr/bin` |
| swap 是 0 | fallocate 失败 | `dd if=/dev/zero of=/swapfile bs=1M count=2048` |

**A. Docker 装不上（手动方式兜底）**
```bash
# 用腾讯云镜像源的 docker-ce 仓库，把 9 换成你的系统大版本
cat > /etc/yum.repos.d/docker-ce.repo <<'EOF'
[docker-ce-stable]
name=Docker CE Stable
baseurl=https://mirrors.cloud.tencent.com/docker-ce/linux/centos/9/x86_64/stable
enabled=1
gpgcheck=0
EOF
dnf install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
systemctl enable --now docker
```

**B. 镜像拉不下来（几乎一定会遇到）**
```bash
# 先测一下
timeout 60 docker pull hello-world
# 如果超时/报错，改用腾讯云容器镜像仓库（内网，最稳）
docker pull ccr.ccs.tencentyun.com/library/hello-world
docker tag ccr.ccs.tencentyun.com/library/hello-world hello-world
docker run --rm hello-world
```
> 能通就说明走 ccr.ccs.tencentyun.com 这条路可行。
> 后面项目里用到的镜像都按同样方式拉 + 打标签（项目 README 里有具体命令）。

### 步骤 1-4：D1 收尾自检
```bash
echo "--- D1 自检 ---"
docker compose version >/dev/null 2>&1 && echo "✔ compose 就绪" || echo "✘ compose 缺失"
free -m | awk '/Swap/{print "✔ swap", $2"MB" }'
sysctl -n net.core.somaxconn | grep -q 65535 && echo "✔ 内核参数生效" || echo "✘ 内核参数未生效"
```

---

## D2 · 起项目一集群（1 小时）

### 步骤 2-1：进目录 + 准备日志目录权限

```bash
cd /opt/ops/project1-cluster

# ★ 必须做：mysqld 以 uid 999 运行，挂载出来的日志目录属主不对会直接起不来
mkdir -p logs/{mysql-node1,mysql-node2,nginx-lb,nginx-node1,nginx-node2}
chown -R 999:999 logs/mysql-node1 logs/mysql-node2
ls -ld logs/mysql-node1
```

**预期**：`drwxr-xr-x. 2 999 999 ...`
对不上（显示 root）→ chown 没执行成功，确认你在正确的目录下。

### 步骤 2-2：拉镜像（先单独拉，能看清卡在哪）

```bash
docker pull nginx:1.25-alpine
docker pull mysql:8.0
```
> 拉不动就换成：
> `docker pull ccr.ccs.tencentyun.com/library/nginx:1.25-alpine`
> `docker tag ccr.ccs.tencentyun.com/library/nginx:1.25-alpine nginx:1.25-alpine`
> mysql 同理。

### 步骤 2-3：起集群

```bash
docker compose up -d --build
```

**MySQL 首次初始化要 60~90 秒**，这期间容器状态是 `(health: starting)`。

```bash
# 等的时候盯着看
watch -n 3 'docker compose ps'
# 或者
docker compose ps
```

**预期输出**（全部 Up）：
```
NAME         IMAGE              STATUS
lb           nginx:1.25-alpine  Up
node1-web    nginx:1.25-alpine  Up
node1-app    cluster-p1-node1-app  Up
node1-db     mysql:8.0          Up (healthy)
node2-web    nginx:1.25-alpine  Up
node2-app    cluster-p1-node2-app  Up
node2-db     mysql:8.0          Up (healthy)
```

### 步骤 2-4：验证负载均衡

```bash
for i in $(seq 1 10); do curl -s http://127.0.0.1/whoami; done
```

**预期输出**（node1 / node2 交替）：
```
node=node1-web time=2026-10-18T12:00:00+08:00
node=node2-web time=2026-10-18T12:00:00+08:00
node=node1-web time=...
...
```

浏览器打开 `http://你的公网IP`，刷新几次，页面上的"当前响应节点"应该在两个之间跳。

### 步骤 2-5：验证业务接口

```bash
curl -s http://127.0.0.1/health | python3 -m json.tool
curl -s "http://127.0.0.1/api/orders?user_id=1" | python3 -m json.tool
```

**预期**：看到 JSON，`"db": "ok"`，orders 里有数据。

### 步骤 2-6：看内存（2G 机器必须盯）

```bash
docker stats --no-stream
free -h
```

**预期**：总占用不超过 1.2G，available 还有 400MB 以上。

### 步骤 2-7：卡住了怎么办

| 症状 | 排查命令 | 处理 |
|---|---|---|
| 容器一直 `(health: starting)` | `docker logs node1-db --tail 30` | 多半是初始化中，再等等；超 3 分钟就查日志 |
| `node1-db` 反复 Restarting | `docker logs node1-db --tail 50` | 见下方三条 |
| 报 `Errcode: 13` | — | 日志目录属主 → 回到步骤 2-1 做 chown |
| 报 `unknown variable` | — | my.cnf 参数问题 → `mysql/master.cnf` 里注释掉报错的参数 |
| 报 `Address already in use` | `ss -tlnp \| grep :80` | 端口占用 → kill 掉占用进程 |
| 报 `Pool overlaps` | — | 见下方"网段冲突" |
| `curl` 返回 502 | `docker logs lb --tail 20` | 后端没起来，按上面逐项查 |

**网段冲突**（腾讯云内网用了 172.16/12 时会撞车）：
```bash
# 报错信息：Pool overlaps with other one on this address space
# 改掉四个网段，比如改成 10.20/10.21/10.22/10.23
sed -i 's/172\.20\.0/10.20.0/g; s/172\.21\.0/10.21.0/g; s/172\.22\.0/10.22.0/g; s/172\.23\.0/10.23.0/g' docker-compose.yml
# 注意 nginx/lb.conf 里的 allow 172.20.0.0/24 也要跟着改
sed -i 's|allow 172.20.0.0/24|allow 10.20.0.0/24|' nginx/lb.conf
docker compose down && docker compose up -d
```

### 步骤 2-8：D2 收尾自检
```bash
echo "--- D2 自检 ---"
N=$(docker compose ps --format '{{.State}}' | grep -c running)
echo "运行中容器: ${N}/7"
[ "$N" -eq 7 ] && echo "✔ 全部就绪" || echo "✘ 有容器没起来，查：docker compose ps"
for i in 1 2 3 4 5 6; do curl -s http://127.0.0.1/whoami; done
```

---

## D3 · 搭建 MySQL 主从（30 分钟）

### 步骤 3-1：跑脚本

```bash
bash scripts/setup_replication.sh
```

脚本会：创建复制账号 → 主库 dump → 导入从库 → 配置 GTID 复制 → 验证。

**预期尾部输出**：
```
             Replica_IO_Running: Yes
            Replica_SQL_Running: Yes
        Seconds_Behind_Master: 0
                 Auto_Position: 1
主从复制搭建成功！
```

### 步骤 3-2：亲手验证数据同步（截图留证）

```bash
# 主库写入
docker exec -e MYSQL_PWD=Root@123456 node1-db mysql -uroot -e \
  "INSERT INTO shop.orders (user_id,product,amount,status) VALUES (99,'repl-test',1.11,'paid');"

# 从库查（应该立刻能看到）
docker exec -e MYSQL_PWD=Root@123456 node2-db mysql -uroot -e \
  "SELECT id,product,created_at FROM shop.orders WHERE user_id=99;"
```

**预期**：从库能看到 `repl-test` 这条记录。查不到 → 看下面。

### 步骤 3-3：验证读写分离

```bash
# 从库节点应该拒绝写
curl -X POST http://127.0.0.1/api/order -d '{"user_id":1}' -v 2>&1 | grep HTTP
```
> 多做几次（因为会轮询到主库节点），看到 `403` 说明从库节点拒绝了写请求。

### 步骤 3-4：卡住了怎么办

```bash
# 第一件事：看从库状态
docker exec -e MYSQL_PWD=Root@123456 node2-db mysql -uroot -e "SHOW REPLICA STATUS\G" | grep -E 'Running|Error|Seconds_Behind'

# 网络通不通（容器间）
docker exec node2-db sh -c 'getent hosts node1-db'
```

| 症状 | 原因 | 处理 |
|---|---|---|
| `Replica_IO_Running: Connecting` | 连不上主库 | 查网络、账号、密码、防火墙 |
| `server-id 相同` 报错 | 两个配置文件没生效 | 确认 `SELECT @@server_id` 两边不同 |
| `Access denied for user 'repl'` | 复制账号没建成 | 重跑脚本第 1 步 |
| `Replica_SQL_Running: No` + 1062 | 数据冲突 | 见故障演练手册场景 5 |

### 步骤 3-5：D3 收尾自检
```bash
docker exec -e MYSQL_PWD=Root@123456 node2-db mysql -uroot -e "SHOW REPLICA STATUS\G" \
  | grep -E 'Replica_IO_Running|Replica_SQL_Running|Seconds_Behind_Master'
```

---

## D4 · 备份、健康检查、告警、crontab（1 小时）

### 步骤 4-1：配钉钉告警

1. 钉钉建个群（哪怕只有你一个人）→ 群设置 → 智能群助手 → 添加机器人 → 自定义
2. 安全设置选「自定义关键词」，填：**告警**
3. 复制 Webhook 地址

```bash
mkdir -p /opt/ops
cat > /opt/ops/.env.notify <<'EOF'
DINGTALK_WEBHOOK="https://oapi.dingtalk.com/robot/send?access_token=你的token"
EOF
chmod 600 /opt/ops/.env.notify

# 测试（手机应该立刻响）
bash scripts/notify.sh "告警通道测试" "收到这条说明告警链路打通了"
```

**预期**：终端打印 `[notify] 钉钉发送成功`，手机收到消息。
收不到 → 检查 Webhook 地址、关键词是否是"告警"。

### 步骤 4-2：手动跑一次备份

```bash
bash scripts/backup.sh
```

**预期输出**：
```
[2026-10-18 12:00:00] =========== 备份开始 ===========
[2026-10-18 12:00:01] [1/4] 备份 MySQL 容器 node1-db
[2026-10-18 12:00:05]   ✔ 数据库备份完成：/opt/ops/backup/mysql/mysql_20261018_120000.sql.gz (1MB)
[2026-10-18 12:00:05] [2/4] 备份代码与配置
[2026-10-18 12:00:06]   ✔ 代码备份完成：... (1MB)
[2026-10-18 12:00:06] [3/4] 清理 7 天前的备份
[2026-10-18 12:00:06] ✔ 备份成功 | 耗时 6s | MySQL 1MB + 代码 1MB
```

```bash
ls -lh /opt/ops/backup/mysql/
```

### 步骤 4-3：手动跑一次健康检查

```bash
bash scripts/health_check.sh
```

**预期**：全部 ✔，最后一行 `✔ 全部检查通过`。

### 步骤 4-4：挂 crontab

```bash
crontab -e
```
粘贴以下内容（按 `i` 编辑，`:wq` 保存）：
```cron
# ★ 第一行必须写：cron 的 PATH 极短，不声明会找不到 docker/mysqldump
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# 每日 02:00 全量备份
0 2 * * * /opt/ops/project1-cluster/scripts/backup.sh >> /opt/ops/logs/scripts/backup-cron.log 2>&1

# 每 5 分钟健康检查
*/5 * * * * /opt/ops/project1-cluster/scripts/health_check.sh >> /opt/ops/logs/scripts/health-cron.log 2>&1
```

```bash
crontab -l
# 等 6 分钟后确认真的在跑
tail -5 /opt/ops/logs/scripts/health-cron.log
```

### 步骤 4-5：★ 验证 cron 真的会触发（新手 90% 栽在这里）

```bash
# 临时改成每分钟，验证完再改回去
crontab -l | sed 's|\*/5|\*|' | crontab -
sleep 70
tail -3 /opt/ops/logs/scripts/health-cron.log

# ★ 验证完记得改回 5 分钟
crontab -l | sed 's|^\* \* \* \* \*|*/5 * * * *|' | crontab -
crontab -l | grep health
```

**cron 不执行的三大原因**（背下来，面试常问）：
1. **环境变量**：cron 的 PATH 极短 —— 所以 crontab 第一行必须写 `PATH=...`
2. **CRLF 换行**：Windows 编辑过的脚本在 Linux 上直接报 `bad interpreter: /bin/bash^M`
3. **没有执行权限**：`chmod +x`
4. 还有一个：**脚本用了相对路径**，cron 的工作目录是用户的 home，不是脚本所在目录

```bash
# 看 cron 到底执行了没
journalctl -u crond --since "10 min ago" | tail -20
# 或
grep CROND /var/log/cron | tail -10
```

### 步骤 4-6：★ 做一次备份恢复演练

```bash
# 起临时容器，把备份灌进去验证
docker run -d --name restore-test -e MYSQL_ROOT_PASSWORD=Test@123 mysql:8.0
sleep 50
zcat $(ls -t /opt/ops/backup/mysql/mysql_*.sql.gz | head -1) | \
  docker exec -i restore-test mysql -uroot -pTest@123 --force
docker exec -e MYSQL_PWD=Test@123 restore-test mysql -uroot -e "SELECT COUNT(*) FROM shop.orders;"
docker rm -f restore-test
```

**预期**：能查到订单数量，说明备份真能恢复。
这一步做不到，前面所有备份工作都白干。

---

## D5 · 故障演练与复盘（一整天，这是简历的核心产出）

> **这一天是整套方案里最值钱的一天。**
> 故障不会自己送上门，你得亲手造出来，再亲手查出来。

### 步骤 5-1：LB 摘除演练

```bash
bash scripts/failover_drill.sh node1-web 20
```

**预期**：停掉 node1 后，20 次请求全部返回 200，且都打到 node2。

### 步骤 5-2：按手册逐个制造故障

打开 `docs/故障演练手册.md`，里面有 6 个场景（每个都有"制造→现象→排查→解决"）：

| 编号 | 故障 | 简历对应 | 建议顺序 |
|---|---|---|---|
| 1 | 端口占用 | ★简历原文 | 1 |
| 2A | MySQL 数据目录属主错误 | ★简历原文 | 2 |
| 2B | SELinux 导致 403 | ★简历原文（权限异常） | 3 |
| 3 | 磁盘占满 | 加分项 | 4 |
| 4 | 配置参数废弃致重启失败 | 加分项 | 5 |
| 5 | 主从复制断裂（1062） | ★最强加分项 | 6 |
| 6 | 连接数打满 | 加分项 | 7 |

**每个场景的操作节奏**：
```
制造故障（按手册的"制造"小节敲命令）
  ↓
不看答案，自己先猜可能是什么原因
  ↓
按"排查"小节的命令一条条敲，把每一步输出截图
  ↓
按"解决"小节修复
  ↓
用"故障复盘模板.md"写一份复盘文档
```

### 步骤 5-3：写复盘文档

```bash
cd docs
cp 故障复盘模板.md 故障复盘-端口占用.md
vim 故障复盘-端口占用.md
```

**至少写 3 篇**：端口占用、权限异常、主从断裂。

**每篇必须包含**：时间线（精确到分钟）、根因（5 个 Why）、改进措施（预防/发现/流程三类）。

### 步骤 5-4：D5 收尾
```bash
ls docs/
# 应该看到 故障复盘-端口占用.md 故障复盘-权限异常.md 故障复盘-主从断裂.md
# 把 docs/故障演练手册.md 末尾的"演练记录表"填满
```

---

## D6 · 项目二 LNMP（1 小时）

### 步骤 6-1：先停项目一（2G 内存跑不动两套）

```bash
cd /opt/ops/project1-cluster
docker compose down
docker ps    # 应该是空的
```

### 步骤 6-2：起 LNMP

```bash
cd /opt/ops/project2-lnmp
mkdir -p logs/{mysql,nginx}
chown -R 999:999 logs/mysql
docker compose up -d --build
```

> PHP 镜像要编译扩展，**首次构建 2~5 分钟**，别以为卡死了，看着输出等。

```bash
docker compose ps
```
**预期**：三个容器 Up，mysql 是 `(healthy)`。

### 步骤 6-3：验证

```bash
curl -s http://127.0.0.1:8080/nginx-health
curl -s http://127.0.0.1:8080/ | head -30
```
浏览器打开 `http://你的公网IP:8080`。

**预期**：页面显示 PHP 版本、MySQL 版本、orders 表行数（此时是 6 行种子数据）。

### 步骤 6-4：造 30 万行数据

```bash
docker exec -i lnmp-mysql mysql -uroot -pRoot@123456 < sql/gen_data.sql
```

**耗时 1~3 分钟**。中间没有任何输出是正常的，等它跑完。

```bash
docker exec -e MYSQL_PWD=Root@123456 lnmp-mysql mysql -uroot -e "SELECT COUNT(*) FROM shop.orders;"
```
**预期**：300000。

> 如果报错 `cte_max_recursion_depth`，说明 CTE 递归深度没设够——
> 脚本里已经写了 `SET SESSION cte_max_recursion_depth = 1000000`，
> 报这个错说明你没走脚本而是手敲的 SQL。

### 步骤 6-5：造慢查询

```bash
for i in 1 2 3; do
  docker exec -e MYSQL_PWD=Root@123456 lnmp-mysql mysql -uroot -e \
    "SELECT * FROM shop.orders WHERE status='paid' ORDER BY amount DESC LIMIT 5000;" > /dev/null
done

docker exec lnmp-mysql sh -c 'mysqldumpslow -s t -t 5 /var/log/mysql/slow.log'
```

**预期**：slow.log 里有内容，mysqldumpslow 能汇总出 Top 5。

### 步骤 6-6：卡住了怎么办

| 症状 | 处理 |
|---|---|
| 502 Bad Gateway | `docker logs lnmp-nginx --tail 20`，多半是 php-fpm 没起来 |
| `File not found` | nginx 的 `SCRIPT_FILENAME` 配错，检查 default.conf |
| PHP 连不上 MySQL | `docker exec lnmp-php sh -c 'getent hosts mysql'` |
| mysql 起不来 Errcode 13 | 回到 6-2 的 `chown -R 999:999 logs/mysql` |

---

## D7 · SQL 优化（1 小时）

### 步骤 7-1：优化前基线（★ 先跑，别急着建索引）

```bash
bash scripts/bench.sh before
```

输出保存在 `docs/benchmark_before.txt`。
**先看一眼 Q1 的 EXPLAIN**，应该看到：
```
type: ALL          ← 全表扫描
rows: 299xxx       ← 扫描 30 万行
Extra: Using where; Using filesort
```

### 步骤 7-2：加索引

```bash
docker exec -i lnmp-mysql mysql -uroot -pRoot@123456 < sql/optimize.sql
```

> 执行时间几十秒（30 万行建 3 个索引）。
> 打开 `sql/optimize.sql`，里面每条 CREATE INDEX 都写了**为什么这么设计**。

### 步骤 7-3：优化后复测

```bash
bash scripts/bench.sh after
```

**再对比 Q1 的 EXPLAIN**，应该看到：
```
type: ref
rows: 几百
Extra: Using index condition
```

### 步骤 7-4：填对比表

打开 `docs/SQL优化记录.md`，把两个文件里的真实数字填进表格：

```bash
# 快速对比关键指标
grep -A3 "Q1" docs/benchmark_before.txt | head -20
grep -A3 "Q1" docs/benchmark_after.txt  | head -20
```

**必须填的字段**：type、rows、Extra、耗时。
**不要编数字** —— 2C2G 跑出来是多少就写多少，面试官追问"为什么提升 X 倍"你才答得上来。

### 步骤 7-5：备份 + 恢复演练（项目二）

```bash
bash scripts/mysql_backup.sh
bash scripts/restore_test.sh
crontab -e
# 加一行：
# 0 3 * * * /opt/ops/project2-lnmp/scripts/mysql_backup.sh >> /opt/ops/logs/scripts/lnmp-backup-cron.log 2>&1
```

### 步骤 7-6：D7 收尾
```bash
ls docs/
# 应该有 benchmark_before.txt benchmark_after.txt SQL优化记录.md（已填好数字）
```

---

# 第三部分：收尾

## 全套验证清单（打满才算完成）

**项目一**
- [ ] 7 个容器全部 Up，其中两个 mysql 是 healthy
- [ ] 连续请求能看到 node1/node2 轮转
- [ ] 主从复制双 Yes，主库写入从库立即可见
- [ ] 从库节点拒绝写请求（读写分离生效）
- [ ] 备份脚本手动执行成功
- [ ] **恢复演练通过**
- [ ] 告警真的收到过至少一次
- [ ] crontab 已挂且有日志输出
- [ ] 至少 3 个故障演练 + 3 篇复盘文档

**项目二**
- [ ] 三个容器 Up，mysql healthy
- [ ] 8080 页面能显示 PHP/MySQL 版本
- [ ] 30 万行数据造好
- [ ] 慢查询日志有内容
- [ ] bench 前后都跑过，**对比表填了真实数字**
- [ ] 备份 + 恢复演练通过

**面试准备**
- [ ] 目录推到 GitHub
- [ ] 关键输出截图存好（docker ps、SHOW REPLICA STATUS、bench 对比）
- [ ] 过一遍 `interview/高频追问与答法.md` 末尾的自查表
- [ ] 过一遍 `interview/命令与SQL速查.md` 末尾的自查表

## 排错速查（外网访问不通时，按这个顺序排查）

```
1. 腾讯云控制台防火墙      → 端口放行了没？（最容易被漏）
2. 系统 firewalld          → firewall-cmd --list-ports
3. 容器端口映射            → docker compose ps 看 0.0.0.0:80->80/tcp
4. 容器进程                → docker logs <容器名> --tail 30
5. 容器内部服务            → docker exec <容器> ss -tlnp
```
> 判断技巧：`curl` 卡住超时 = 被防火墙丢包；`Connection refused` = 进程没监听；
> `502` = 网关通了但后端挂了；`504` = 后端慢。

## 常用命令速记

```bash
# 看全部容器实时状态
docker compose ps
docker stats

# 看日志（最常用）
docker logs <容器名> --tail 50 -f

# 进容器
docker exec -it <容器名> sh

# 一键清理（跑路前的后悔药）
docker compose down -v        # ⚠ 会把数据卷也删了

# 系统状态
free -h && df -h && uptime
```

## 最后三句提醒

1. **所有数字必须自己跑出来**，别抄、别编。面试官问"提升了多少"时，你答得出推导过程才是真本事。
2. **备份不做恢复演练 = 没备份**，这是运维的底线。
3. **把目录推到 GitHub**。面试时说"我给你看一下仓库"，比说一百句"我做过的"都管用。
