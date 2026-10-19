# 项目二：基于 Docker Compose 的 LNMP 环境部署与自动化运维

> 对应简历：「Docker Compose 编排 Nginx+PHP-FPM+MySQL 8.0，配置网络与数据卷；
> Shell 脚本每日备份保留 7 天；docker logs 排查容器启动失败/端口冲突/权限异常；
> SQL 索引优化」

---

## 一、架构与数据卷设计

```
   客户端 ──8080──▶  lnmp-nginx (172.30.0.10)
                          │  fastcgi_pass php:9000
                          ▼
                     lnmp-php (172.30.0.11)  ──▶ lnmp-mysql (172.30.0.12, :3306 仅内网)
                          │                            │
                     ./www (bind mount)          mysql-data (named volume)
                          │                            │
                     php.ini (只读挂载)           my.cnf + schema.sql(初始化)
```

### 挂载方式的选择（面试常问 bind mount vs volume）

| 挂载内容 | 方式 | 理由 |
|---|---|---|
| `./www` 网站代码 | **bind mount** | 改代码立即生效，开发/测试环境效率高 |
| `mysql-data` 数据库 | **named volume** | 由 Docker 管理，不受宿主机权限/SELinux 干扰，备份迁移方便 |
| `my.cnf` / nginx conf | **bind mount :ro** | 配置要进版本管理，且只读挂载防容器内误改 |
| 初始化 SQL | bind mount 到 `/docker-entrypoint-initdb.d/` | 官方镜像机制：首次启动自动执行 |

> **为什么数据库不用 bind mount？** 因为宿主机目录会引入属主（uid 999 的 mysql 用户）
> 和 SELinux 标签问题，是容器化 MySQL 最常见的启动失败原因。用 named volume 由 Docker
> 自动处理权限，省掉一大类故障。**这个取舍本身就是一道面试题的答案。**

---

## 二、部署步骤

### Step 1：确认项目一已停止（2G 内存跑不动两套）
```bash
cd /opt/ops/project1-cluster && docker compose down
cd /opt/ops/project2-lnmp
```

### Step 2：准备日志目录权限，然后拉起
```bash
# ★ 必须做：mysqld 以 uid 999 运行，日志目录属主不对会起不来
mkdir -p logs/{mysql,nginx}
chown -R 999:999 logs/mysql

docker compose up -d --build
docker compose ps        # 三个容器都要 Up，mysql 要 healthy
```
> PHP 镜像要编译扩展，首次构建约 2~5 分钟，耐心等。

### Step 3：验证
```bash
curl -I http://127.0.0.1:8080/nginx-health
curl -s http://127.0.0.1:8080/ | head -20
# 浏览器打开 http://公网IP:8080
```

### Step 4：造压测数据
```bash
docker exec -i lnmp-mysql mysql -uroot -pRoot@123456 < sql/gen_data.sql
# 1~3 分钟。完成后确认：
docker exec -e MYSQL_PWD=Root@123456 lnmp-mysql mysql -uroot -e \
  "SELECT COUNT(*) FROM shop.orders;"
```

### Step 5：优化前基线（★ 先跑，别急着建索引）
```bash
bash scripts/bench.sh before
# 结果在 docs/benchmark_before.txt
```

### Step 6：造慢查询（让慢日志有内容）
```bash
for i in 1 2 3; do
  docker exec -e MYSQL_PWD=Root@123456 lnmp-mysql mysql -uroot -e \
    "SELECT * FROM shop.orders WHERE status='paid' ORDER BY amount DESC LIMIT 5000;" > /dev/null
done
docker exec lnmp-mysql sh -c 'mysqldumpslow -s t -t 5 /var/log/mysql/slow.log'
```

### Step 7：加索引并复测
```bash
docker exec -i lnmp-mysql mysql -uroot -pRoot@123456 < sql/optimize.sql
bash scripts/bench.sh after
# 把数字填进 docs/SQL优化记录.md
```

### Step 8：备份 + 恢复演练
```bash
bash scripts/mysql_backup.sh        # 手动跑一次
bash scripts/restore_test.sh        # ★ 必做：验证备份真的能恢复
crontab -e
# 写入（第一行 PATH 必须有，否则 cron 找不到 docker/mysqldump）：
# PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
# 0 3 * * * /opt/ops/project2-lnmp/scripts/mysql_backup.sh >> /opt/ops/logs/scripts/lnmp-backup-cron.log 2>&1
```

---

## 三、排错（简历：容器启动失败 / 端口冲突 / 权限异常）

### 3.1 容器启动失败

```bash
# 第一件事：看日志
docker logs lnmp-mysql --tail 50
docker logs lnmp-php --tail 30
docker logs lnmp-nginx --tail 30

# 看退出码和状态
docker inspect lnmp-mysql --format '{{.State.Status}} | ExitCode={{.State.ExitCode}} | Error={{.State.Error}}'

# 一直 Restarting 时，看上一次的日志
docker logs --previous lnmp-mysql 2>/dev/null

# ★ 容器起不来又想进去看：用临时容器把卷挂出来
docker run --rm -v lnmp_p2_mysql_data:/data -it alpine sh
```

**常见原因清单**
| 现象 | 原因 | 排查命令 |
|---|---|---|
| mysql 一直 Restarting | my.cnf 参数名错误 | `docker logs` 里的 `unknown variable` |
| mysql 报 Errcode 13 | 数据目录属主不对（bind mount 时） | `namei -l /var/lib/mysql` |
| php 报 Connection refused | php-fpm 监听 127.0.0.1，跨容器连不上 | `netstat -tlnp` in php 容器 |
| nginx 502 Bad Gateway | fastcgi_pass 地址/端口错 | `docker logs lnmp-nginx` 里的 upstream 错误 |
| nginx 报 File not found | SCRIPT_FILENAME 没配对 | 检查 fastcgi_param 配置 |

### 3.2 端口冲突

```bash
# 宿主机端口被占
ss -tlnp | grep ':8080'
lsof -i:8080

# Docker 报端口已分配，但没容器在跑 —— 端口被僵尸进程占着
docker ps -a
ss -tan state time-wait | wc -l

# 容器内部端口冲突（两个进程抢 9000）
docker exec lnmp-php sh -c 'netstat -tlnp 2>/dev/null || ss -tlnp'
```

**解决**：改 `docker-compose.yml` 的端口映射，或 kill 占用进程。
我在方案里把 LNMP 放到 8080 而不是 80，就是因为 80 已被项目一的 LB 占用
——**多环境共存时提前规划端口，是最省事的防冲突办法**。

### 3.3 权限异常

```bash
# 容器内文件权限
docker exec lnmp-php sh -c 'ls -l /var/www/html && id www-data'

# 逐层看路径权限（很多运维不知道这个命令）
docker exec lnmp-nginx sh -c 'namei -l /var/www/html/index.php'

# SELinux（OpenCloudOS 开启时）
getenforce
ausearch -m AVC -ts recent | head -20
# 解决：挂载加 :z  /  chcon -Rt svirt_sandbox_file_t <目录>
```

### 3.4 网络不通（fastcgi 连不上 / PHP 连不上 MySQL）

```bash
# 容器间 DNS 解析
docker exec lnmp-nginx sh -c 'getent hosts php || nslookup php'
docker exec lnmp-php   sh -c 'getent hosts mysql'

# 端口连通性（alpine 没 nc，用 python 或 wget 验证）
docker exec lnmp-php sh -c 'wget -qO- -T 3 http://mysql:3306 && echo open || echo closed'

# 看网络拓扑
docker network inspect lnmp-p2_lnmp-net
```

---

## 四、验证清单

- [ ] 三个容器 Up，mysql healthy
- [ ] `http://IP:8080` 能看到 PHP + MySQL 版本和订单数
- [ ] orders 表 30 万行数据造好
- [ ] `bench.sh before` 有输出，慢查询日志有内容
- [ ] 索引已建，`bench.sh after` 有输出
- [ ] **对比表已填真实数字**
- [ ] 备份脚本执行成功，7 天保留生效
- [ ] **恢复演练通过**
- [ ] crontab 已挂

---

## 五、面试高频追问

**Q：Docker Compose 的 bridge 网络，容器之间怎么通信？**
> Compose 会创建一个自定义 bridge 网络，并启动内嵌 DNS server。
> 容器之间可以直接用**服务名**或 **container_name** 解析（比如 `fastcgi_pass php:9000`、
> `DB_HOST=mysql`），不需要写死 IP——这就是我给每个服务配固定 IP 之外的另一层保障。
> 自定义 bridge 和默认 docker0 的区别：自定义网络支持容器名 DNS 解析，docker0 不支持。

**Q：容器重启后数据还在吗？**
> 网站代码用的是 bind mount，直接映射到宿主机目录，容器删了文件还在。
> 数据库用的是 named volume `lnmp_p2_mysql_data`，由 Docker 管理在
> `/var/lib/docker/volumes/` 下，`docker compose down` 不会删 volume，
> 只有 `down -v` 才会删。所以两个容器都删掉重建，数据依然在。

**Q：mysqldump 会影响线上业务吗？**
> 用 `--single-transaction`：在 RR 隔离级别下开启一致性快照，
> 导出的是一个时间点的一致数据，且**不锁表**，InnoDB 表业务无感知。
> 前提是全 InnoDB；如果有 MyISAM 表，必须 `--lock-all-tables`，那就会锁表。
> 另外我加了 `--quick` 让 mysqldump 逐行读取而不是一次性加载大表到内存，
> 这对 2G 内存的机器很重要，否则大表导出会 OOM。

**Q：备份文件你怎么确认能用？**
> 我做了恢复演练（`restore_test.sh`）：起一个临时 MySQL 容器，
> 把最新备份灌进去，然后对比关键表的行数是否和生产一致。
> 备份不验证等于没备份——这是我做完备份脚本后补上的一步，
> 因为第一次演练时就发现了 `--set-gtid-purged` 导致导入冲突的问题。

**Q：为什么 PHP-FPM 要改监听地址？**
> 官方 `php:fpm` 镜像默认监听 `127.0.0.1:9000`，只有本机（容器内）能连。
> Nginx 在另一个容器里，跨容器访问必须监听 `0.0.0.0:9000`。
> 我通过覆盖 `zz-docker.conf`（文件名排序在最后，优先级最高）来改，
> 同时把 `pm.max_children` 调到 8，适配 2G 内存。

**Q：OPcache 有什么用？开了有什么风险？**
> PHP 每次请求都要把脚本编译成 opcode，OPcache 把编译结果缓存到共享内存，
> 省掉重复编译，性能通常能提升 3~5 倍，是 PHP 性价比最高的优化。
> 风险是代码更新后可能还用旧缓存，所以测试环境我开 `validate_timestamps=1`，
> 生产环境建议关掉并配合发布流程主动 `opcache_reset()`。
