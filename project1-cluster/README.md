# 项目一：多机模拟 Web 业务集群运维与故障排查

> 对应简历：「2 台 CentOS 节点（Nginx+MySQL），firewall 安全策略及内核参数，
> Shell + crontab 自动备份与告警，排查权限/端口故障并输出复盘文档」

---

## 一、架构

```
                        ┌──────────────────────────────┐
      客户端 ──80──▶    │  lb (nginx)                  │  172.20.0.10
                        │  upstream: node1-web,node2-web│
                        │  被动健康检查 max_fails=2     │
                        └───────┬──────────────┬───────┘
                    front 网络   │              │  172.20.0.0/24
                        ┌───────▼──────┐  ┌────▼────────┐
                        │ node1-web    │  │ node2-web   │
                        │ 172.20.0.11  │  │ 172.20.0.12 │
                        └───────┬──────┘  └────┬────────┘
                  net-node1     │              │   net-node2
                        172.21.0.0/24          │   172.22.0.0/24
                        ┌───────▼──────┐  ┌────▼────────┐
                        │ node1-app    │  │ node2-app   │  (python, :8080)
                        │ alias: app   │  │ alias: app  │  ★ 同名 alias 让
                        └───────┬──────┘  └────┬────────┘    两份 nginx 配置
                                │              │              可以复用
                        ┌───────▼──────┐  ┌────▼────────┐
                        │ node1-db     │  │ node2-db    │
                        │ MySQL 主     │  │ MySQL 从    │
                        └───────┬──────┘  └────┬────────┘
                                └──────┬───────┘
                              net-db   │  172.23.0.0/24
                            （主从复制专网，业务流量进不来）
```

**为什么这么设计（面试会问）**

| 设计点 | 理由 |
|---|---|
| 4 个独立网络 | 模拟真实集群的网络分区：前端网、各节点内网、数据库复制专网 |
| db 不在 front 网络 | 数据库绝不能直接暴露给前端网段，这是安全基线 |
| 复制走独立网络 | 复制流量与业务流量隔离，避免大事务同步时拖垮业务 |
| 用 alias `app` | 两个节点的 nginx 配置保持完全一致，配置改动只需改一处 |
| MySQL 参数大幅裁剪 | 2G 内存跑两个 MySQL 实例，不裁剪必 OOM |

---

## 二、部署步骤（按顺序执行）

### Step 0：上传目录 + 准备日志目录权限
```bash
cd /opt/ops/project1-cluster

# ★ 必须做：MySQL 容器里 mysqld 以 uid 999 运行，
#   如果挂载出来的日志目录属主是 root，mysqld 写 error.log 会报 Errcode 13 直接启动失败
mkdir -p logs/{mysql-node1,mysql-node2,nginx-lb,nginx-node1,nginx-node2}
chown -R 999:999 logs/mysql-node1 logs/mysql-node2
```
> 忘了这步的话，MySQL 会起不来，`docker logs node1-db` 里是
> `Can't create/write to file '/var/log/mysql/error.log' (Errcode: 13)`。
> ——别慌，这正好就是「权限异常」故障演练的第一次实弹，按手册场景 2A 排查即可。

### Step 1：拉起集群
```bash
docker compose up -d --build
# 首次启动 MySQL 要初始化，等 60~90 秒
docker compose ps      # 确认 6 个容器都是 Up (healthy)
```

**如果镜像拉不下来**（国内访问 Docker Hub 经常失败）：
```bash
# 改用腾讯云容器镜像仓库（内网，最稳）
docker pull ccr.ccs.tencentyun.com/library/nginx:1.25-alpine
docker pull ccr.ccs.tencentyun.com/library/mysql:8.0
docker tag ccr.ccs.tencentyun.com/library/nginx:1.25-alpine nginx:1.25-alpine
docker tag ccr.ccs.tencentyun.com/library/mysql:8.0 mysql:8.0
docker compose up -d --build
```

### Step 2：验证负载均衡
```bash
# 连续请求 10 次，应该看到 node1-web / node2-web 交替
for i in $(seq 1 10); do curl -s http://127.0.0.1/whoami; done

# 浏览器打开 http://你的公网IP  —— 刷新能看到节点变化
```

### Step 3：搭建主从复制
```bash
bash scripts/setup_replication.sh
# 看到 Replica_IO_Running: Yes / Replica_SQL_Running: Yes 即成功
```

验证数据同步：
```bash
docker exec -e MYSQL_PWD=Root@123456 node1-db mysql -uroot -e \
  "INSERT INTO shop.orders (user_id,product,amount,status) VALUES (99,'repl-test',1.11,'paid');"
docker exec -e MYSQL_PWD=Root@123456 node2-db mysql -uroot -e \
  "SELECT id,product,created_at FROM shop.orders WHERE user_id=99;"
```

### Step 4：配置告警（钉钉机器人）
```bash
# 1. 钉钉群 → 群设置 → 智能群助手 → 添加机器人 → 自定义 → 复制 Webhook
mkdir -p /opt/ops
cat > /opt/ops/.env.notify <<'EOF'
DINGTALK_WEBHOOK="https://oapi.dingtalk.com/robot/send?access_token=你的token"
EOF
chmod 600 /opt/ops/.env.notify

# 2. 测试能否收到
bash scripts/notify.sh "告警通道测试" "如果你收到这条消息，说明告警链路打通了"
```

### Step 5：挂 crontab
```bash
crontab -e
```
写入：
```cron
# ★ 第一行必须写：cron 的 PATH 极短，不声明会找不到 docker/mysqldump
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# 每日 02:00 全量备份
0 2 * * * /opt/ops/project1-cluster/scripts/backup.sh >> /opt/ops/logs/scripts/backup-cron.log 2>&1

# 每 5 分钟健康检查
*/5 * * * * /opt/ops/project1-cluster/scripts/health_check.sh >> /opt/ops/logs/scripts/health-cron.log 2>&1
```

确认：
```bash
crontab -l
# 手动跑一次验证
bash scripts/backup.sh
bash scripts/health_check.sh
ls -lh /opt/ops/backup/mysql/
```

### Step 6：故障演练（★ 最重要的一步）
```bash
# LB 摘除演练
bash scripts/failover_drill.sh node1-web 20

# 然后按 docs/故障演练手册.md 逐个制造 6 个故障并排查
# 每处理完一个，用 docs/故障复盘模板.md 写一份复盘
```

---

## 三、内核参数与防火墙（简历对应点）

```bash
# 查看已生效的内核参数
sysctl -a 2>/dev/null | grep -E 'somaxconn|tcp_tw_reuse|file-max|ip_forward'

# 查看防火墙
firewall-cmd --list-all
```

**每个参数为什么这么配（背下来，面试会追问）**
- `net.core.somaxconn=65535`：默认 128，Nginx 高并发下 accept 队列会溢出
- `net.ipv4.tcp_tw_reuse=1`：短连接场景下 TIME_WAIT 会堆积到几万个，复用可缓解
- `net.ipv4.tcp_syncookies=1`：防 SYN Flood
- `fs.file-max=655350`：每个连接一个 fd，句柄不够会报 too many open files
- `vm.swappiness=10`：尽量用内存，但保留 swap 兜底（2G 机器必须有 swap）

---

## 四、验证清单（做完打勾）

- [ ] 6 个容器全部 Up (healthy)
- [ ] 连续请求能看到两个节点轮转
- [ ] 主从复制双 Yes，主库写入从库能查到
- [ ] 从库写入被拒绝（读写分离生效）
- [ ] 备份脚本手动执行成功，备份文件在
- [ ] **恢复演练成功**（见下方，必做）
- [ ] 告警能真的收到
- [ ] crontab 已挂，日志有输出
- [ ] 6 个故障演练至少完成 3 个，复盘文档写好
- [ ] `docker stats` 内存占用在预算内

### ★ 恢复演练（备份不验证等于没备份）
```bash
# 在一个临时库里恢复验证
docker run -d --name restore-test -e MYSQL_ROOT_PASSWORD=Test@123 -e MYSQL_ALLOW_EMPTY_PASSWORD=1 mysql:8.0
sleep 40
zcat /opt/ops/backup/mysql/mysql_*.sql.gz | docker exec -i restore-test mysql -uroot -pTest@123
docker exec -e MYSQL_PWD=Test@123 restore-test mysql -uroot -e "SELECT COUNT(*) FROM shop.orders;"
docker rm -f restore-test
```

---

## 五、资源释放

项目二要跑 LNMP，**两个项目不能同时运行**（2G 内存）：
```bash
cd /opt/ops/project1-cluster && docker compose down
# 想彻底清数据卷（下次重搭主从）加 -v
# docker compose down -v
```

---

## 六、面试高频追问（完整版见 interview/目录）

**Q：你只有一台机器，怎么叫"集群"？**
> 见总 README 第一节。要主动说明方案的边界，诚实比吹牛得分高。

**Q：为什么 MySQL 要用 GTID 复制？**
> 传统复制要记录 binlog 文件名和 position，主库故障后选新主时定位很麻烦。
> GTID 每个事务有全局唯一 ID，从库只要 `MASTER_AUTO_POSITION=1` 就能自动找到该从哪继续，
> 故障切换不用人工算位点。代价是对事务有约束（`enforce_gtid_consistency`），
> 比如不能在一个事务里同时更新 InnoDB 和 MyISAM 表。

**Q：主从延迟怎么监控、怎么优化？**
> 监控：`Seconds_Behind_Master`（注意它是个估算值，从库 IO 线程断时显示为 NULL）。
> 优化：① 开启基于 LOGICAL_CLOCK 的并行复制（我配了 2 个 worker）；
> ② 大事务拆小；③ 从库加索引（主从索引一致，避免从库回放慢）；
> ④ binlog_row_image=MINIMAL 减少日志量。

**Q：备份为什么用 --single-transaction？**
> InnoDB 在 RR 隔离级别下，mysqldump 开启一个一致性快照事务，
> 导出的所有表都处于同一时间点，且**不锁表**，业务无感知。
> 如果有 MyISAM 表则无效，必须 `--lock-all-tables`。

**Q：--set-gtid-purged=OFF 是什么考虑？**
> 默认是 ON，会把主库已执行的 GTID 集合写进 dump 文件头部。
> 导入到一个已有 GTID 的库时会冲突报错。
> 我做的是全量恢复场景，关掉更省事；如果是做从库扩容，反而要保留（ON 或 AUTO）。
